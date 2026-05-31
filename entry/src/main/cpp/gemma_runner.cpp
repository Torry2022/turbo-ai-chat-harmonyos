#include "gemma_runner.h"

#include <fstream>
#include <functional>
#include <ostream>
#include <sstream>
#include <streambuf>

#include <llm/llm.hpp>

using MNN::Transformer::Llm;
using MNN::Transformer::MultimodalPrompt;
using MNN::Transformer::PromptImagePart;

namespace {

class ChunkStreamBuffer : public std::streambuf {
public:
    explicit ChunkStreamBuffer(const std::function<void(const std::string&)>& onChunk) : onChunk_(onChunk) {}

    const std::string& output() const {
        return output_;
    }

protected:
    std::streamsize xsputn(const char* s, std::streamsize n) override {
        if (n <= 0) {
            return 0;
        }
        std::string chunk(s, static_cast<size_t>(n));
        output_ += chunk;
        if (onChunk_) {
            onChunk_(chunk);
        }
        return n;
    }

    int overflow(int c) override {
        if (c == EOF) {
            return c;
        }
        char value = static_cast<char>(c);
        xsputn(&value, 1);
        return c;
    }

private:
    std::function<void(const std::string&)> onChunk_;
    std::string output_;
};

} // namespace

GemmaRunner::GemmaRunner() = default;
GemmaRunner::~GemmaRunner() = default;

bool GemmaRunner::load(const std::string& configPath, int threadNum, int maxNewTokens, std::string& error) {
    std::lock_guard<std::mutex> lock(mutex_);
    error.clear();

    std::ifstream configFile(configPath);
    if (!configFile.good()) {
        error = "config.json not found: " + configPath;
        return false;
    }

    std::unique_ptr<Llm> candidate(Llm::createLLM(configPath));
    if (!candidate) {
        error = "Llm::createLLM returned null";
        return false;
    }

    std::ostringstream config;
    config << "{"
           << "\"tmp_path\":\"tmp\","
           << "\"backend_type\":\"cpu\","
           << "\"thread_num\":" << threadNum << ","
           << "\"precision\":\"low\","
           << "\"memory\":\"low\","
           << "\"max_new_tokens\":" << maxNewTokens << ","
           << "\"max_all_tokens\":2048,"
           << "\"prompt_cache\":true,"
           << "\"async\":false"
           << "}";
    candidate->set_config(config.str());

    if (!candidate->load()) {
        error = "MNN LLM load failed";
        return false;
    }

    llm_ = std::move(candidate);
    return true;
}

std::string GemmaRunner::generate(const std::string& prompt, int maxNewTokens, std::string& error) {
    std::lock_guard<std::mutex> lock(mutex_);
    error.clear();

    if (!llm_) {
        error = "model is not loaded";
        return "";
    }

    if (maxNewTokens > 0) {
        llm_->set_config("{\"max_new_tokens\":" + std::to_string(maxNewTokens) + ",\"async\":false}");
    }

    std::ostringstream output;
    llm_->response(prompt, &output, nullptr, maxNewTokens);
    return output.str();
}

std::string GemmaRunner::generateStreaming(
    const std::string& prompt,
    int maxNewTokens,
    const std::function<void(const std::string&)>& onChunk,
    std::string& error) {
    std::lock_guard<std::mutex> lock(mutex_);
    error.clear();

    if (!llm_) {
        error = "model is not loaded";
        return "";
    }

    if (maxNewTokens > 0) {
        llm_->set_config("{\"max_new_tokens\":" + std::to_string(maxNewTokens) + ",\"async\":false}");
    }

    ChunkStreamBuffer buffer(onChunk);
    std::ostream output(&buffer);
    llm_->response(prompt, &output, nullptr, maxNewTokens);
    output.flush();
    return buffer.output();
}

std::string GemmaRunner::generateChatStreaming(
    const std::vector<ChatTurn>& messages,
    int maxNewTokens,
    const std::function<void(const std::string&)>& onChunk,
    std::string& error) {
    std::lock_guard<std::mutex> lock(mutex_);
    error.clear();

    if (!llm_) {
        error = "model is not loaded";
        return "";
    }

    if (messages.empty()) {
        error = "chat messages are empty";
        return "";
    }

    if (maxNewTokens > 0) {
        llm_->set_config("{\"max_new_tokens\":" + std::to_string(maxNewTokens) + ",\"async\":false}");
    }

    MNN::Transformer::ChatMessages chatMessages;
    chatMessages.reserve(messages.size());
    for (const auto& message : messages) {
        if (!message.role.empty() && !message.content.empty()) {
            chatMessages.emplace_back(message.role, message.content);
        }
    }

    if (chatMessages.empty()) {
        error = "chat messages contain no usable content";
        return "";
    }

    ChunkStreamBuffer buffer(onChunk);
    std::ostream output(&buffer);
    llm_->response(chatMessages, &output, nullptr, maxNewTokens);
    output.flush();
    return buffer.output();
}

std::string GemmaRunner::generateImageChatStreaming(
    const std::vector<ChatTurn>& messages,
    const ImageData& image,
    int maxNewTokens,
    const std::function<void(const std::string&)>& onChunk,
    std::string& error) {
    std::lock_guard<std::mutex> lock(mutex_);
    error.clear();

    if (!llm_) {
        error = "model is not loaded";
        return "";
    }
    if (messages.empty()) {
        error = "chat messages are empty";
        return "";
    }
    if (image.width <= 0 || image.height <= 0 || image.rgb.size() != static_cast<size_t>(image.width * image.height * 3)) {
        error = "invalid image payload";
        return "";
    }

    if (maxNewTokens > 0) {
        llm_->set_config("{\"max_new_tokens\":" + std::to_string(maxNewTokens) + ",\"async\":false}");
    }

    std::string userContent;
    for (auto it = messages.rbegin(); it != messages.rend(); ++it) {
        if (it->role == "user" && !it->content.empty()) {
            userContent = it->content;
            break;
        }
    }
    if (userContent.empty()) {
        error = "chat messages contain no user content";
        return "";
    }

    auto imageVar = MNN::Express::_Input({image.height, image.width, 3}, MNN::Express::NHWC, halide_type_of<uint8_t>());
    auto* imagePtr = imageVar->writeMap<uint8_t>();
    if (imagePtr == nullptr) {
        error = "failed to map image tensor";
        return "";
    }
    std::copy(image.rgb.begin(), image.rgb.end(), imagePtr);

    MultimodalPrompt prompt;
    prompt.prompt_template = "<img>image_0</img>\n"
                             "请始终使用简体中文回答。"
                             "如果问题要求识别或提取图片中的文字，请只根据图片中可见内容回答，不要翻译成其他语言。"
                             "不要使用 Markdown 列表；如果只能识别到部分内容，就只输出识别到的文字，不要输出空项目或占位符。\n"
                             + userContent;
    PromptImagePart imagePart;
    imagePart.image_data = imageVar;
    imagePart.width = image.width;
    imagePart.height = image.height;
    prompt.images["image_0"] = imagePart;

    ChunkStreamBuffer buffer(onChunk);
    std::ostream output(&buffer);
    const auto* contextBefore = llm_->getContext();
    const auto visionUsBefore = contextBefore == nullptr ? 0 : contextBefore->vision_us;
    llm_->response(prompt, &output, nullptr, maxNewTokens);
    output.flush();
    const auto* contextAfter = llm_->getContext();
    const auto visionUsAfter = contextAfter == nullptr ? 0 : contextAfter->vision_us;
    if (visionUsAfter <= visionUsBefore) {
        error = "MNN vision encoder did not run. Rebuild libMNN.so with LLM_SUPPORT_VISION=ON and MNN_BUILD_OPENCV=ON.";
        return "";
    }
    return buffer.output();
}

void GemmaRunner::reset() {
    std::lock_guard<std::mutex> lock(mutex_);
    llm_.reset();
}

bool GemmaRunner::isLoaded() const {
    std::lock_guard<std::mutex> lock(mutex_);
    return llm_ != nullptr;
}
