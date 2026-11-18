#pragma once

#include <memory>
#include <mutex>
#include <string>
#include <vector>

namespace MNN::Transformer { class Embedding; }

struct EmbeddingResult {
    std::vector<std::vector<float>> vectors;
    size_t inputTokens = 0;
};

class EmbeddingModel {
public:
    EmbeddingModel(const std::string& configPath, int threads);
    ~EmbeddingModel();
    EmbeddingResult encode(const std::vector<std::string>& texts);
    int dimension() const;
    int threads() const;
    const std::string& configPath() const;

private:
    std::unique_ptr<MNN::Transformer::Embedding> model_;
    std::string configPath_;
    int threads_ = 0;
    mutable std::mutex mutex_;
};

void loadEmbedding(const std::string& configPath, int threads);
EmbeddingResult encodeEmbedding(const std::vector<std::string>& texts);
void releaseEmbedding();
int embeddingDimension();
int embeddingThreads();
