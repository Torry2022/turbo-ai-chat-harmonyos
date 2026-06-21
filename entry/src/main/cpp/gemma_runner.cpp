#include "gemma_runner.h"

#include <algorithm>
#include <cctype>
#include <exception>
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

class UserStopException : public std::exception {
public:
    const char* what() const noexcept override {
        return "user stopped generation";
    }
};

bool IsUtf8Continuation(unsigned char value) {
    return (value & 0xC0) == 0x80;
}

bool IsValidUtf8Sequence(const std::string& text, size_t index, size_t length) {
    if (index + length > text.size()) {
        return false;
    }

    const auto first = static_cast<unsigned char>(text[index]);
    if (length == 1) {
        return first <= 0x7F;
    }
    if (length == 2) {
        return IsUtf8Continuation(static_cast<unsigned char>(text[index + 1]));
    }
    if (length == 3) {
        const auto second = static_cast<unsigned char>(text[index + 1]);
        const auto third = static_cast<unsigned char>(text[index + 2]);
        if (!IsUtf8Continuation(second) || !IsUtf8Continuation(third)) {
            return false;
        }
        return (first != 0xE0 || second >= 0xA0) && (first != 0xED || second <= 0x9F);
    }
    if (length == 4) {
        const auto second = static_cast<unsigned char>(text[index + 1]);
        const auto third = static_cast<unsigned char>(text[index + 2]);
        const auto fourth = static_cast<unsigned char>(text[index + 3]);
        if (!IsUtf8Continuation(second) || !IsUtf8Continuation(third) || !IsUtf8Continuation(fourth)) {
            return false;
        }
        return (first != 0xF0 || second >= 0x90) && (first != 0xF4 || second <= 0x8F);
    }
    return false;
}

size_t Utf8SequenceLength(unsigned char value) {
    if (value <= 0x7F) {
        return 1;
    }
    if (value >= 0xC2 && value <= 0xDF) {
        return 2;
    }
    if (value >= 0xE0 && value <= 0xEF) {
        return 3;
    }
    if (value >= 0xF0 && value <= 0xF4) {
        return 4;
    }
    return 0;
}

size_t ValidUtf8PrefixLength(const std::string& text) {
    size_t index = 0;
    while (index < text.size()) {
        const size_t length = Utf8SequenceLength(static_cast<unsigned char>(text[index]));
        if (length == 0) {
            index++;
            continue;
        }
        if (index + length > text.size()) {
            break;
        }
        if (!IsValidUtf8Sequence(text, index, length)) {
            index++;
            continue;
        }
        index += length;
    }
    return index;
}

class ChunkStreamBuffer : public std::streambuf {
public:
    explicit ChunkStreamBuffer(
        const std::function<void(const std::string&)>& onChunk,
        const std::function<bool()>& shouldStop = nullptr)
        : onChunk_(onChunk), shouldStop_(shouldStop) {}

    const std::string& output() const {
        return output_;
    }

protected:
    std::streamsize xsputn(const char* s, std::streamsize n) override {
        if (n <= 0) {
            return 0;
        }
        if (ShouldStop()) {
            throw UserStopException();
        }
        std::string chunk(s, static_cast<size_t>(n));
        output_ += chunk;
        pendingChunk_ += chunk;
        FlushPendingChunk(false);
        if (ShouldStop()) {
            throw UserStopException();
        }
        return n;
    }

    int overflow(int c) override {
        if (c == EOF) {
            return c;
        }
        if (ShouldStop()) {
            throw UserStopException();
        }
        char value = static_cast<char>(c);
        xsputn(&value, 1);
        if (ShouldStop()) {
            throw UserStopException();
        }
        return c;
    }

    int sync() override {
        FlushPendingChunk(true);
        if (ShouldStop()) {
            throw UserStopException();
        }
        return 0;
    }

private:
    bool ShouldStop() const {
        return shouldStop_ && shouldStop_();
    }

    void FlushPendingChunk(bool force) {
        if (!onChunk_) {
            pendingChunk_.clear();
            return;
        }

        const size_t prefixLength = ValidUtf8PrefixLength(pendingChunk_);
        if (prefixLength > 0) {
            onChunk_(pendingChunk_.substr(0, prefixLength));
            pendingChunk_.erase(0, prefixLength);
        }
        if (force && !pendingChunk_.empty()) {
            onChunk_(pendingChunk_);
            pendingChunk_.clear();
        }
    }

    std::function<void(const std::string&)> onChunk_;
    std::function<bool()> shouldStop_;
    std::string output_;
    std::string pendingChunk_;
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

void AddUniqueStopSequence(std::vector<std::string>& stopSequences, const std::string& stopSequence) {
    if (stopSequence.empty()) {
        return;
    }
    if (std::find(stopSequences.begin(), stopSequences.end(), stopSequence) != stopSequences.end()) {
        return;
    }
    stopSequences.push_back(stopSequence);
}

std::vector<std::string> BuildStopSequences(const Llm* llm, const std::string& explicitEndWith) {
    std::vector<std::string> stopSequences;
    AddUniqueStopSequence(stopSequences, explicitEndWith);

    const auto* context = llm == nullptr ? nullptr : llm->getContext();
    if (context != nullptr) {
        AddUniqueStopSequence(stopSequences, context->end_with);
    }

    AddUniqueStopSequence(stopSequences, "<turn|>");
    AddUniqueStopSequence(stopSequences, "<|im_end|>");
    AddUniqueStopSequence(stopSequences, "<|endoftext|>");
    return stopSequences;
}

bool StripTrailingStopSequence(std::string& text, const std::string& stopSequence) {
    if (text.empty() || stopSequence.empty()) {
        return false;
    }

    size_t suffixEnd = text.size();
    while (suffixEnd > 0 && std::isspace(static_cast<unsigned char>(text[suffixEnd - 1])) != 0) {
        suffixEnd--;
    }
    if (suffixEnd < stopSequence.size()) {
        return false;
    }

    const size_t stopStart = suffixEnd - stopSequence.size();
    if (text.compare(stopStart, stopSequence.size(), stopSequence) != 0) {
        return false;
    }

    text.erase(stopStart);
    return true;
}

int TokenCount(Llm* llm, const std::string& text) {
    if (llm == nullptr || text.empty()) {
        return 0;
    }
    return static_cast<int>(llm->tokenizer_encode(text).size());
}

std::string BuildSamplingConfigProperties(const GemmaRunner::SamplingConfig& sampling) {
    std::ostringstream config;
    config << "\"max_new_tokens\":" << sampling.maxNewTokens << ","
           << "\"reuse_kv\":false,"
           << "\"sampler_type\":\"mixed\","
           << "\"mixed_samplers\":[\"penalty\",\"topK\",\"topP\",\"temperature\"],"
           << "\"temperature\":" << sampling.temperature << ","
           << "\"top_k\":" << sampling.topK << ","
           << "\"top_p\":" << sampling.topP << ","
           << "\"repetition_penalty\":" << sampling.repetitionPenalty << ","
           << "\"presence_penalty\":" << sampling.presencePenalty << ","
           << "\"frequency_penalty\":" << sampling.frequencyPenalty << ","
           << "\"penalty_window\":" << sampling.penaltyWindow << ","
           << "\"async\":false";
    return config.str();
}

std::string BuildRuntimeConfig(int threadNum, const GemmaRunner::SamplingConfig& sampling) {
    const int maxAllTokens = std::max(2048, sampling.maxNewTokens + 2048);
    std::ostringstream config;
    config << "{"
           << "\"tmp_path\":\"tmp\","
           << "\"backend_type\":\"cpu\","
           << "\"thread_num\":" << threadNum << ","
           << "\"precision\":\"low\","
           << "\"memory\":\"low\","
           << BuildSamplingConfigProperties(sampling) << ","
           << "\"max_all_tokens\":" << maxAllTokens << ","
           << "\"prompt_cache\":false"
           << "}";
    return config.str();
}

std::string BuildGenerationConfig(const GemmaRunner::SamplingConfig& sampling) {
    return "{" + BuildSamplingConfigProperties(sampling) + "}";
}

void DumpRawPromptDebug(
    const std::string& prompt,
    const std::string& output,
    const std::vector<int>& inputIds,
    const GemmaRunner::SamplingConfig& sampling,
    const GemmaRunner::GenerationResult& result,
    const Llm* llm) {
    std::ofstream dump("/data/storage/el2/base/haps/entry/files/raw_output_debug.txt",
                       std::ios::out | std::ios::trunc);
    if (!dump.good()) {
        return;
    }

    const auto* context = llm == nullptr ? nullptr : llm->getContext();
    dump << "=== SAMPLING ===\n";
    dump << "requested_max_new_tokens=" << sampling.maxNewTokens << "\n";
    dump << "temperature=" << sampling.temperature << "\n";
    dump << "top_p=" << sampling.topP << "\n";
    dump << "top_k=" << sampling.topK << "\n";
    dump << "repetition_penalty=" << sampling.repetitionPenalty << "\n";
    dump << "frequency_penalty=" << sampling.frequencyPenalty << "\n";
    dump << "presence_penalty=" << sampling.presencePenalty << "\n";
    dump << "penalty_window=" << sampling.penaltyWindow << "\n";
    dump << "end_with_context=" << (context == nullptr ? "" : context->end_with) << "\n";
    dump << "context_status=" << (context == nullptr ? -1 : static_cast<int>(context->status)) << "\n";
    dump << "context_output_tokens="
         << (context == nullptr ? 0 : static_cast<int>(context->output_tokens.size())) << "\n";
    dump << "input_prompt_tokens=" << inputIds.size() << "\n\n";

    dump << "=== PROMPT ===\n" << prompt << "\n\n";
    dump << "=== RAW OUTPUT (" << output.size() << " chars, "
         << result.generatedTokens << " tokens, stop=" << result.stopReason << ") ===\n"
         << output << "\n";
    dump << "=== END ===\n";
}

int ResolveGeneratedTokens(Llm* llm, const std::string& text, int maxNewTokens, int removedStopTokens) {
    int contextTokens = 0;
    const auto* context = llm == nullptr ? nullptr : llm->getContext();
    if (context != nullptr) {
        contextTokens = static_cast<int>(context->output_tokens.size());
    }

    if (contextTokens > 0) {
        const int adjustedContextTokens = std::max(0, contextTokens - removedStopTokens);
        if (maxNewTokens <= 0 || adjustedContextTokens <= maxNewTokens) {
            return adjustedContextTokens;
        }
    }

    const int estimatedTokens = TokenCount(llm, text);
    if (maxNewTokens > 0 && estimatedTokens > maxNewTokens) {
        return maxNewTokens;
    }
    return estimatedTokens;
}

GemmaRunner::GenerationResult BuildGenerationResult(
    Llm* llm,
    const std::string& text,
    int maxNewTokens,
    const std::string& explicitEndWith = "") {
    GemmaRunner::GenerationResult result;
    result.text = text;
    const auto* context = llm == nullptr ? nullptr : llm->getContext();
    if (context == nullptr) {
        result.generatedTokens = TokenCount(llm, result.text);
        return result;
    }

    result.stopReason = MapStopReason(context->status);
    int removedStopTokens = 0;
    for (const auto& stopSequence : BuildStopSequences(llm, explicitEndWith)) {
        while (StripTrailingStopSequence(result.text, stopSequence)) {
            result.stopReason = "eos";
            removedStopTokens += TokenCount(llm, stopSequence);
        }
    }

    result.generatedTokens = ResolveGeneratedTokens(llm, result.text, maxNewTokens, removedStopTokens);
    if (result.stopReason == "unknown" && maxNewTokens > 0 && result.generatedTokens >= maxNewTokens) {
        result.stopReason = "max_tokens";
    }
    return result;
}

void ApplyUserStop(GemmaRunner::GenerationResult& result, bool stopped) {
    if (stopped) {
        result.stopReason = "user_stop";
    }
}

} // namespace

GemmaRunner::GemmaRunner() = default;
GemmaRunner::~GemmaRunner() = default;

bool GemmaRunner::load(
    const std::string& configPath,
    int threadNum,
    const SamplingConfig& sampling,
    std::string& error) {
    std::lock_guard<std::mutex> lock(mutex_);
    error.clear();
    stopRequested_.store(false);

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

    candidate->set_config(BuildRuntimeConfig(threadNum, sampling));

    if (!candidate->load()) {
        error = "MNN LLM load failed";
        return false;
    }

    llm_ = std::move(candidate);
    return true;
}

std::string GemmaRunner::generate(const std::string& prompt, const SamplingConfig& sampling, std::string& error) {
    std::lock_guard<std::mutex> lock(mutex_);
    error.clear();

    if (!llm_) {
        error = "model is not loaded";
        return {};
    }

    if (sampling.maxNewTokens > 0) {
        llm_->set_config(BuildGenerationConfig(sampling));
    }

    stopRequested_.store(false);
    llm_->reset();
    std::ostringstream output;
    llm_->response(prompt, &output, nullptr, sampling.maxNewTokens);
    return output.str();
}

GemmaRunner::GenerationResult GemmaRunner::generateStreaming(
    const std::string& prompt,
    const SamplingConfig& sampling,
    const std::function<void(const std::string&)>& onChunk,
    std::string& error) {
    std::lock_guard<std::mutex> lock(mutex_);
    error.clear();

    if (!llm_) {
        error = "model is not loaded";
        return {};
    }

    if (sampling.maxNewTokens > 0) {
        llm_->set_config(BuildGenerationConfig(sampling));
    }

    stopRequested_.store(false);
    llm_->reset();
    ChunkStreamBuffer buffer(onChunk, [this]() {
        return stopRequested_.load();
    });
    std::ostream output(&buffer);
    output.exceptions(std::ios::badbit | std::ios::failbit);
    try {
        llm_->response(prompt, &output, nullptr, sampling.maxNewTokens);
        output.flush();
    } catch (const UserStopException&) {
    } catch (const std::ios_base::failure& ex) {
        if (!stopRequested_.load()) {
            error = ex.what();
            return {};
        }
    }
    const std::string rawOutput = buffer.output();
    GenerationResult result = BuildGenerationResult(llm_.get(), rawOutput, sampling.maxNewTokens);
    const bool stopped = stopRequested_.load();
    ApplyUserStop(result, stopped);
    stopRequested_.store(false);
    return result;
}

GemmaRunner::GenerationResult GemmaRunner::generateRawPromptStreaming(
    const std::string& prompt,
    const SamplingConfig& sampling,
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

    if (sampling.maxNewTokens > 0) {
        llm_->set_config(BuildGenerationConfig(sampling));
    }

    stopRequested_.store(false);
    llm_->reset();
    const std::vector<int> inputIds = llm_->tokenizer_encode(prompt);
    if (inputIds.empty()) {
        error = "tokenizer returned empty prompt";
        return {};
    }

    ChunkStreamBuffer buffer(onChunk, [this]() {
        return stopRequested_.load();
    });
    std::ostream output(&buffer);
    output.exceptions(std::ios::badbit | std::ios::failbit);
    const char* endWithPtr = endWith.empty() ? nullptr : endWith.c_str();
    try {
        llm_->response(inputIds, &output, endWithPtr, sampling.maxNewTokens);
        output.flush();
    } catch (const UserStopException&) {
    } catch (const std::ios_base::failure& ex) {
        if (!stopRequested_.load()) {
            error = ex.what();
            return {};
        }
    }
    const std::string rawOutput = buffer.output();
    GenerationResult result = BuildGenerationResult(llm_.get(), rawOutput, sampling.maxNewTokens, endWith);
    const bool stopped = stopRequested_.load();
    ApplyUserStop(result, stopped);
    stopRequested_.store(false);
    DumpRawPromptDebug(prompt, rawOutput, inputIds, sampling, result, llm_.get());

    return result;
}

GemmaRunner::GenerationResult GemmaRunner::generateChatStreaming(
    const std::vector<ChatTurn>& messages,
    const SamplingConfig& sampling,
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

    if (sampling.maxNewTokens > 0) {
        llm_->set_config(BuildGenerationConfig(sampling));
    }

    MNN::Transformer::ChatMessages chatMessages;
    chatMessages.reserve(messages.size());
    std::ostringstream debugPrompt;
    debugPrompt << "MNN ChatMessages\n";
    for (const auto& message : messages) {
        if (!message.role.empty() && !message.content.empty()) {
            chatMessages.emplace_back(message.role, message.content);
            debugPrompt << message.role << ":\n" << message.content << "\n\n";
        }
    }

    if (chatMessages.empty()) {
        error = "chat messages contain no usable content";
        return {};
    }

    stopRequested_.store(false);
    ChunkStreamBuffer buffer(onChunk, [this]() {
        return stopRequested_.load();
    });
    std::ostream output(&buffer);
    output.exceptions(std::ios::badbit | std::ios::failbit);
    llm_->reset();
    try {
        llm_->response(chatMessages, &output, nullptr, sampling.maxNewTokens);
        output.flush();
    } catch (const UserStopException&) {
    } catch (const std::ios_base::failure& ex) {
        if (!stopRequested_.load()) {
            error = ex.what();
            return {};
        }
    }
    const std::string rawOutput = buffer.output();
    GenerationResult result = BuildGenerationResult(llm_.get(), rawOutput, sampling.maxNewTokens);
    const bool stopped = stopRequested_.load();
    ApplyUserStop(result, stopped);
    stopRequested_.store(false);
    DumpRawPromptDebug(
        debugPrompt.str(),
        rawOutput,
        llm_->tokenizer_encode(debugPrompt.str()),
        sampling,
        result,
        llm_.get());
    return result;
}

GemmaRunner::GenerationResult GemmaRunner::generateImageChatStreaming(
    const std::vector<ChatTurn>& messages,
    const ImageData& image,
    const SamplingConfig& sampling,
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

    if (sampling.maxNewTokens > 0) {
        llm_->set_config(BuildGenerationConfig(sampling));
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
                             "回答结尾请使用与回答语言匹配的句末标点。"
                             "如果问题要求识别或提取图片中的文字，请只根据图片中可见内容回答，不要翻译成其他语言。"
                             "不要使用 Markdown 列表；如果只能识别到部分内容，就只输出识别到的文字，不要输出空项目或占位符。\n"
                             + userContent;
    PromptImagePart imagePart;
    imagePart.image_data = imageVar;
    imagePart.width = image.width;
    imagePart.height = image.height;
    prompt.images["image_0"] = imagePart;

    stopRequested_.store(false);
    ChunkStreamBuffer buffer(onChunk, [this]() {
        return stopRequested_.load();
    });
    std::ostream output(&buffer);
    output.exceptions(std::ios::badbit | std::ios::failbit);
    llm_->reset();
    const auto* contextBefore = llm_->getContext();
    const auto visionUsBefore = contextBefore == nullptr ? 0 : contextBefore->vision_us;
    try {
        llm_->response(prompt, &output, nullptr, sampling.maxNewTokens);
        output.flush();
    } catch (const UserStopException&) {
    } catch (const std::ios_base::failure& ex) {
        if (!stopRequested_.load()) {
            error = ex.what();
            return {};
        }
    }
    const auto* contextAfter = llm_->getContext();
    const auto visionUsAfter = contextAfter == nullptr ? 0 : contextAfter->vision_us;
    const bool stopped = stopRequested_.load();
    if (!stopped && visionUsAfter <= visionUsBefore) {
        error = "MNN vision encoder did not run. Rebuild libMNN.so with LLM_SUPPORT_VISION=ON and MNN_BUILD_OPENCV=ON.";
        return {};
    }
    const std::string rawOutput = buffer.output();
    GenerationResult result = BuildGenerationResult(llm_.get(), rawOutput, sampling.maxNewTokens);
    ApplyUserStop(result, stopped);
    stopRequested_.store(false);
    return result;
}

void GemmaRunner::requestStop() {
    stopRequested_.store(true);
}

void GemmaRunner::reset() {
    std::lock_guard<std::mutex> lock(mutex_);
    stopRequested_.store(false);
    llm_.reset();
}

bool GemmaRunner::isLoaded() const {
    std::lock_guard<std::mutex> lock(mutex_);
    return llm_ != nullptr;
}
