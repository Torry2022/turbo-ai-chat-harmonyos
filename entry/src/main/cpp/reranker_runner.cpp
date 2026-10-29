#include "reranker_runner.h"
#include "llm/reranker.hpp"
#include <atomic>
#include <cmath>
#include <mutex>
#include <stdexcept>

namespace {
std::mutex mutex;
std::unique_ptr<MNN::Transformer::Qwen3Reranker> model;
std::atomic<uint64_t> cancelEpoch{0};
int tokenLimit = 0;
const std::string instruction = "Given a web search query, retrieve relevant passages that answer the query";
// Must match Qwen3Reranker's separately tokenized prefix, document and suffix.
const std::string prefix = "<|im_start|>system\nJudge whether the Document meets the requirements based on the Query and the Instruct provided. Note that the answer can only be \"yes\" or \"no\".<|im_end|>\n<|im_start|>user\n<Instruct>: ";
const std::string suffix = "<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n";
}

void loadReranker(const std::string& configPath, int threads, int maxInputTokens) {
    std::lock_guard<std::mutex> lock(mutex);
    if (threads < 1 || threads > 16 || maxInputTokens < 128 || maxInputTokens > 8192)
        throw std::runtime_error("Invalid reranker configuration");
    if (model) throw std::runtime_error("Release the loaded reranker first");
    auto candidate = std::make_unique<MNN::Transformer::Qwen3Reranker>(configPath);
    candidate->get_llm()->set_config("{\"backend_type\":\"cpu\",\"thread_num\":" +
        std::to_string(threads) + ",\"precision\":\"low\",\"memory\":\"low\"}");
    candidate->load();
    candidate->setInstruct(instruction);
    model = std::move(candidate);
    tokenLimit = maxInputTokens;
}

std::vector<float> scoreReranker(const std::string& query, const std::vector<std::string>& documents, uint64_t epoch) {
    std::lock_guard<std::mutex> lock(mutex);
    if (!model) throw std::runtime_error("Reranker is not loaded");
    if (query.empty() || documents.empty() || documents.size() > 64)
        throw std::runtime_error("Invalid reranker input");
    const auto shared = model->get_llm()->tokenizer_encode(prefix + instruction + "\n<Query>: " + query + "\n<Document>: ").size()
        + model->get_llm()->tokenizer_encode(suffix).size();
    // Validate the complete request before starting any inference. No silent truncation.
    for (const auto& doc : documents) {
        if (doc.empty() || shared + model->get_llm()->tokenizer_encode(doc).size() > tokenLimit)
            throw std::runtime_error("Reranker input is empty or exceeds the configured token limit");
    }
    if (cancelEpoch.load() != epoch) throw std::runtime_error("Rerank cancelled");
    std::vector<float> result;
    for (const auto& doc : documents) {
        if (cancelEpoch.load() != epoch) throw std::runtime_error("Rerank cancelled");
        auto scores = model->compute_scores(query, {doc});
        if (scores.size() != 1 || !std::isfinite(scores[0]) || scores[0] < 0 || scores[0] > 1)
            throw std::runtime_error("Invalid reranker score");
        result.push_back(scores[0]);
    }
    if (cancelEpoch.load() != epoch) throw std::runtime_error("Rerank cancelled");
    return result;
}

uint64_t rerankerEpoch() { return cancelEpoch.load(); }
void cancelReranker() { cancelEpoch.fetch_add(1); }
void releaseReranker() {
    std::lock_guard<std::mutex> lock(mutex);
    model.reset();
    tokenLimit = 0;
}
