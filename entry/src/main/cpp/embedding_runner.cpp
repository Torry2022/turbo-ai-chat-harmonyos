#include "embedding_runner.h"
#include "mnn_cpu_capacity.h"
#include <llm/llm.hpp>
#include <cmath>
#include <stdexcept>

namespace {
std::mutex lifecycleMutex;
std::shared_ptr<EmbeddingModel> loaded;
constexpr size_t maxInputTokens = 512;
}

EmbeddingModel::EmbeddingModel(const std::string& configPath, int threads) : configPath_(configPath) {
    if (threads < 1 || threads > 16) throw std::runtime_error("向量模型线程配置无效");
    model_.reset(MNN::Transformer::Embedding::createEmbedding(configPath, false));
    if (!model_) throw std::runtime_error("无法创建向量模型");
    if (!model_->set_config("{\"backend_type\":\"cpu\",\"thread_num\":" + std::to_string(threads) +
        ",\"precision\":\"low\",\"memory\":\"low\"}")) throw std::runtime_error("无法应用向量模型运行配置");
    PrepareMnnCpuCapacity(model_->dump_config());
    if (!model_->load()) throw std::runtime_error("向量模型加载失败，请检查模型文件");
    threads_ = model_->cpu_thread_count();
    if (threads_ != threads) throw std::runtime_error("向量模型运行线程与配置不一致");
    encode({"向量模型加载验证"});
}

EmbeddingModel::~EmbeddingModel() = default;

EmbeddingResult EmbeddingModel::encode(const std::vector<std::string>& texts) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (texts.empty() || texts.size() > 64) throw std::runtime_error("请提供 1 至 64 条文本");
    std::vector<std::vector<int>> encoded;
    EmbeddingResult result;
    for (const auto& text : texts) {
        if (text.empty()) throw std::runtime_error("向量输入不能为空");
        auto ids = model_->tokenizer_encode(model_->apply_chat_template(text));
        if (ids.empty() || ids.size() > maxInputTokens) throw std::runtime_error("单条向量输入不能超过 512 tokens");
        result.inputTokens += ids.size();
        encoded.push_back(std::move(ids));
    }
    for (const auto& ids : encoded) {
        auto output = model_->ids_embedding(ids);
        if (!output.get() || !output->getInfo()) throw std::runtime_error("向量模型未返回有效结果");
        const auto size = output->getInfo()->size;
        const float* values = output->readMap<float>();
        if (!values || size != model_->dim() || size <= 0) throw std::runtime_error("向量模型输出维度异常");
        for (int i = 0; i < size; ++i) {
            if (!std::isfinite(values[i])) throw std::runtime_error("向量模型输出包含无效数值");
        }
        result.vectors.emplace_back(values, values + size);
    }
    return result;
}

int EmbeddingModel::dimension() const { return model_->dim(); }
int EmbeddingModel::threads() const { return threads_; }
const std::string& EmbeddingModel::configPath() const { return configPath_; }

void loadEmbedding(const std::string& configPath, int threads) {
    std::lock_guard<std::mutex> lock(lifecycleMutex);
    if (loaded) throw std::runtime_error("请先释放已加载的向量模型");
    loaded = std::make_shared<EmbeddingModel>(configPath, threads);
}

EmbeddingResult encodeEmbedding(const std::vector<std::string>& texts) {
    std::shared_ptr<EmbeddingModel> model;
    {
        std::lock_guard<std::mutex> lock(lifecycleMutex);
        model = loaded;
    }
    if (!model) throw std::runtime_error("请先加载向量模型");
    return model->encode(texts);
}

void releaseEmbedding() {
    std::lock_guard<std::mutex> lock(lifecycleMutex);
    if (loaded && loaded.use_count() > 1) throw std::runtime_error("向量模型正在使用，请等待当前任务结束");
    loaded.reset();
}

int embeddingDimension() { std::lock_guard<std::mutex> lock(lifecycleMutex); return loaded ? loaded->dimension() : 0; }
int embeddingThreads() { std::lock_guard<std::mutex> lock(lifecycleMutex); return loaded ? loaded->threads() : 0; }
