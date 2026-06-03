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

    bool load(const std::string& configPath, int threadNum, int maxNewTokens, std::string& error);
    std::string generate(const std::string& prompt, int maxNewTokens, std::string& error);
    GenerationResult generateStreaming(
        const std::string& prompt,
        int maxNewTokens,
        const std::function<void(const std::string&)>& onChunk,
        std::string& error);
    GenerationResult generateRawPromptStreaming(
        const std::string& prompt,
        int maxNewTokens,
        const std::string& endWith,
        const std::function<void(const std::string&)>& onChunk,
        std::string& error);
    GenerationResult generateChatStreaming(
        const std::vector<ChatTurn>& messages,
        int maxNewTokens,
        const std::function<void(const std::string&)>& onChunk,
        std::string& error);
    GenerationResult generateImageChatStreaming(
        const std::vector<ChatTurn>& messages,
        const ImageData& image,
        int maxNewTokens,
        const std::function<void(const std::string&)>& onChunk,
        std::string& error);
    void reset();
    bool isLoaded() const;

private:
    mutable std::mutex mutex_;
    std::unique_ptr<MNN::Transformer::Llm> llm_;
};
