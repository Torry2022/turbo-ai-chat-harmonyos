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

    GemmaRunner();
    ~GemmaRunner();

    bool load(const std::string& configPath, int threadNum, int maxNewTokens, std::string& error);
    std::string generate(const std::string& prompt, int maxNewTokens, std::string& error);
    std::string generateStreaming(
        const std::string& prompt,
        int maxNewTokens,
        const std::function<void(const std::string&)>& onChunk,
        std::string& error);
    std::string generateChatStreaming(
        const std::vector<ChatTurn>& messages,
        int maxNewTokens,
        const std::function<void(const std::string&)>& onChunk,
        std::string& error);
    void reset();
    bool isLoaded() const;

private:
    mutable std::mutex mutex_;
    std::unique_ptr<MNN::Transformer::Llm> llm_;
};
