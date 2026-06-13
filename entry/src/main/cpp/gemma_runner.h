#pragma once

#include <memory>
#include <mutex>
#include <string>
#include <functional>
#include <vector>

namespace MNN {
namespace Transformer {
class Llm;
}
}

class GemmaRunner {
public:
    struct SamplingConfig {
        int maxNewTokens = 256;
        double temperature = 0.6;
        double topP = 0.9;
        int topK = 40;
        double repetitionPenalty = 1.05;
        double frequencyPenalty = 0.0;
        double presencePenalty = 0.0;
        int penaltyWindow = 256;
    };

    struct ChatTurn {
        std::string role;
        std::string content;
    };

    struct ImageData {
        std::vector<uint8_t> rgb;
        int width = 0;
        int height = 0;
    };

    struct GenerationResult {
        std::string text;
        int generatedTokens = 0;
        std::string stopReason = "unknown";
    };

    GemmaRunner();
    ~GemmaRunner();

    bool load(const std::string& configPath, int threadNum, const SamplingConfig& sampling, std::string& error);
    std::string generate(const std::string& prompt, const SamplingConfig& sampling, std::string& error);
    GenerationResult generateStreaming(
        const std::string& prompt,
        const SamplingConfig& sampling,
        const std::function<void(const std::string&)>& onChunk,
        std::string& error);
    GenerationResult generateRawPromptStreaming(
        const std::string& prompt,
        const SamplingConfig& sampling,
        const std::string& endWith,
        const std::function<void(const std::string&)>& onChunk,
        std::string& error);
    GenerationResult generateChatStreaming(
        const std::vector<ChatTurn>& messages,
        const SamplingConfig& sampling,
        const std::function<void(const std::string&)>& onChunk,
        std::string& error);
    GenerationResult generateImageChatStreaming(
        const std::vector<ChatTurn>& messages,
        const ImageData& image,
        const SamplingConfig& sampling,
        const std::function<void(const std::string&)>& onChunk,
        std::string& error);
    void reset();
    bool isLoaded() const;

private:
    mutable std::mutex mutex_;
    std::unique_ptr<MNN::Transformer::Llm> llm_;
};
