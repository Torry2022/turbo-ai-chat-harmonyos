#include "gemma_runner.h"

#include <fstream>
#include <functional>
#include <ostream>
#include <sstream>
#include <streambuf>

#include <llm/llm.hpp>

using MNN::Transformer::Llm;
using MNN::Transformer::LlmStatus;
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

std::string MapStopReason(LlmStatus status) {
    switch (status) {
        case LlmStatus::NORMAL_FINISHED:
            return "eos";
        case LlmStatus::MAX_TOKENS_FINISHED:
            return "max_tokens";
        case LlmStatus::USER_CANCEL:
            return "user_stop";
        case LlmStatus::TIMEOUT:
            return "timeout";
        case LlmStatus::INTERNAL_ERROR:
            return "internal_error";
        default:
            return "unknown";
    }
}

std::string BuildSamplingConfigProperties(int maxNewTokens) {
    std::ostringstream config;
    config << "\"max_new_tokens\":" << maxNewTokens << ","
           << "\"reuse_kv\":false,"
           << "\"sampler_type\":\"mixed\","
           << "\"mixed_samplers\":[\"penalty\",\"topK\",\"topP\",\"temperature\"],"
           << "\"temperature\":0.6,"
           << "\"top_k\":30,"
           << "\"top_p\":0.85,"
           << "\"repetition_penalty\":1.35,"
           << "\"presence_penalty\":0.15,"
           << "\"frequency_penalty\":0.2,"
           << "\"penalty_window\":256,"
           << "\"async\":false";
    return config.str();
}

std::string BuildRuntimeConfig(int threadNum, int maxNewTokens) {
    std::ostringstream config;
    config << "{"
           << "\"tmp_path\":\"tmp\","
           << "\"backend_type\":\"cpu\","
           << "\"thread_num\":" << threadNum << ","
           << "\"precision\":\"low\","
           << "\"memory\":\"low\","
           << BuildSamplingConfigProperties(maxNewTokens) << ","
           << "\"max_all_tokens\":2048,"
           << "\"prompt_cache\":false"
           << "}";
    return config.str();
}

std::string BuildGenerationConfig(int maxNewTokens) {
    return "{" + BuildSamplingConfigProperties(maxNewTokens) + "}";
}

int ResolveGeneratedTokens(Llm* llm, const std::string& text, int maxNewTokens) {
    int contextTokens = 0;
    const auto* context = llm == nullptr ? nullptr : llm->getContext();
    if (context != nullptr) {
        contextTokens = static_cast<int>(context->output_tokens.size());
    }

    if (contextTokens > 0 && (maxNewTokens <= 0 || contextTokens <= maxNewTokens)) {
        return contextTokens;
    }

    if (llm == nullptr || text.empty()) {
        return 0;
    }

    const int estimatedTokens = static_cast<int>(llm->tokenizer_encode(text).size());
    if (maxNewTokens > 0 && estimatedTokens > maxNewTokens) {
        return maxNewTokens;
    }
    return estimatedTokens;
}

GemmaRunner::GenerationResult BuildGenerationResult(Llm* llm, const std::string& text, int maxNewTokens) {
    GemmaRunner::GenerationResult result;
    result.text = text;
    const auto* context = llm == nullptr ? nullptr : llm->getContext();
    if (context == nullptr) {
        return result;
    }

    result.generatedTokens = ResolveGeneratedTokens(llm, text, maxNewTokens);
    result.stopReason = MapStopReason(context->status);
    if (result.stopReason == "unknown" && maxNewTokens > 0 && result.generatedTokens >= maxNewTokens) {
        result.stopReason = "max_tokens";
    }
    return result;
}

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

    candidate->set_config(BuildRuntimeConfig(threadNum, maxNewTokens));

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
        return {};
    }

    if (maxNewTokens > 0) {
        llm_->set_config(BuildGenerationConfig(maxNewTokens));
    }

    llm_->reset();
    std::ostringstream output;
    llm_->response(prompt, &output, nullptr, maxNewTokens);
    return output.str();
}

GemmaRunner::GenerationResult GemmaRunner::generateStreaming(
    const std::string& prompt,
    int maxNewTokens,
    const std::function<void(const std::string&)>& onChunk,
    std::string& error) {
    std::lock_guard<std::mutex> lock(mutex_);
    error.clear();

    if (!llm_) {
        error = "model is not loaded";
        return {};
    }

    if (maxNewTokens > 0) {
        llm_->set_config(BuildGenerationConfig(maxNewTokens));
    }

    llm_->reset();
    ChunkStreamBuffer buffer(onChunk);
    std::ostream output(&buffer);
    llm_->response(prompt, &output, nullptr, maxNewTokens);
    output.flush();
    return BuildGenerationResult(llm_.get(), buffer.output(), maxNewTokens);
}

GemmaRunner::GenerationResult GemmaRunner::generateRawPromptStreaming(
    const std::string& prompt,
    int maxNewTokens,
    const std::string& endWith,
    const std::function<void(const std::string&)>& onChunk,
    std::string& error) {
    std::lock_guard<std::mutex> lock(mutex_);
    error.clear();

    if (!llm_) {
        error = "model is not loaded";
        return {};
    }
    if (prompt.empty()) {
        error = "prompt is empty";
        return {};
    }

    if (maxNewTokens > 0) {
        llm_->set_config(BuildGenerationConfig(maxNewTokens));
    }

    llm_->reset();
    const std::vector<int> inputIds = llm_->tokenizer_encode(prompt);
    if (inputIds.empty()) {
        error = "tokenizer returned empty prompt";
        return {};
    }

    ChunkStreamBuffer buffer(onChunk);
    std::ostream output(&buffer);
    const char* endWithPtr = endWith.empty() ? nullptr : endWith.c_str();
    llm_->response(inputIds, &output, endWithPtr, maxNewTokens);
    output.flush();
    return BuildGenerationResult(llm_.get(), buffer.output(), maxNewTokens);
}

GemmaRunner::GenerationResult GemmaRunner::generateChatStreaming(
    const std::vector<ChatTurn>& messages,
    int maxNewTokens,
    const std::function<void(const std::string&)>& onChunk,
    std::string& error) {
    std::lock_guard<std::mutex> lock(mutex_);
    error.clear();

    if (!llm_) {
        error = "model is not loaded";
        return {};
    }

    if (messages.empty()) {
        error = "chat messages are empty";
        return {};
    }

    if (maxNewTokens > 0) {
        llm_->set_config(BuildGenerationConfig(maxNewTokens));
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
        return {};
    }

    ChunkStreamBuffer buffer(onChunk);
    std::ostream output(&buffer);
    llm_->reset();
    llm_->response(chatMessages, &output, nullptr, maxNewTokens);
    output.flush();
    return BuildGenerationResult(llm_.get(), buffer.output(), maxNewTokens);
}

GemmaRunner::GenerationResult GemmaRunner::generateImageChatStreaming(
    const std::vector<ChatTurn>& messages,
    const ImageData& image,
    int maxNewTokens,
    const std::function<void(const std::string&)>& onChunk,
    std::string& error) {
    std::lock_guard<std::mutex> lock(mutex_);
    error.clear();

    if (!llm_) {
        error = "model is not loaded";
        return {};
    }
    if (messages.empty()) {
        error = "chat messages are empty";
        return {};
    }
    if (image.width <= 0 || image.height <= 0 || image.rgb.size() != static_cast<size_t>(image.width * image.height * 3)) {
        error = "invalid image payload";
        return {};
    }

    if (maxNewTokens > 0) {
        llm_->set_config(BuildGenerationConfig(maxNewTokens));
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
        return {};
    }

    auto imageVar = MNN::Express::_Input({image.height, image.width, 3}, MNN::Express::NHWC, halide_type_of<uint8_t>());
    auto* imagePtr = imageVar->writeMap<uint8_t>();
    if (imagePtr == nullptr) {
        error = "failed to map image tensor";
        return {};
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
    llm_->reset();
    const auto* contextBefore = llm_->getContext();
    const auto visionUsBefore = contextBefore == nullptr ? 0 : contextBefore->vision_us;
    llm_->response(prompt, &output, nullptr, maxNewTokens);
    output.flush();
    const auto* contextAfter = llm_->getContext();
    const auto visionUsAfter = contextAfter == nullptr ? 0 : contextAfter->vision_us;
    if (visionUsAfter <= visionUsBefore) {
        error = "MNN vision encoder did not run. Rebuild libMNN.so with LLM_SUPPORT_VISION=ON and MNN_BUILD_OPENCV=ON.";
        return {};
    }
    return BuildGenerationResult(llm_.get(), buffer.output(), maxNewTokens);
}

void GemmaRunner::reset() {
    std::lock_guard<std::mutex> lock(mutex_);
    llm_.reset();
}

bool GemmaRunner::isLoaded() const {
    std::lock_guard<std::mutex> lock(mutex_);
    return llm_ != nullptr;
}
