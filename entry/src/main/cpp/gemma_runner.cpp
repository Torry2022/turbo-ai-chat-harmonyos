#include "gemma_runner.h"

#include <fstream>
#include <functional>
#include <ostream>
#include <sstream>
#include <streambuf>

#include <llm/llm.hpp>

using MNN::Transformer::Llm;

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

void GemmaRunner::reset() {
    std::lock_guard<std::mutex> lock(mutex_);
    llm_.reset();
}

bool GemmaRunner::isLoaded() const {
    std::lock_guard<std::mutex> lock(mutex_);
    return llm_ != nullptr;
}
