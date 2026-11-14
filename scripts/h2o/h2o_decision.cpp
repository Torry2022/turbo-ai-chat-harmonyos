#include "h2o_decision.h"
#include "h2o_contract.h"

#include <MNN/expr/ExprCreator.hpp>
#include <llm/llm.hpp>
#include <chrono>
#include <fstream>
#include <limits>
#include <regex>
#include <stdexcept>

namespace H2o {
namespace {
using Llm = MNN::Transformer::Llm;
using Clock = std::chrono::steady_clock;
double elapsedMs(Clock::time_point start) {
    return std::chrono::duration<double, std::milli>(Clock::now() - start).count();
}
}

struct DecisionModel::Runtime {
    std::unique_ptr<Llm, decltype(&Llm::destroy)> model{nullptr, &Llm::destroy};
    std::vector<int> labelTokens;
    int maxInputTokens = 0;
    bool supportsImages = false;
};

DecisionModel::DecisionModel() = default;
DecisionModel::~DecisionModel() = default;

void DecisionModel::load(const std::string& configPath, int threads, int maxInputTokens) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (runtime_) throw std::runtime_error("Release the loaded H2O model first");
    if (configPath.empty() || threads < 1 || threads > 16 || maxInputTokens < 1 || maxInputTokens > 40960) {
        throw std::invalid_argument("Invalid H2O model configuration");
    }
    if (!std::ifstream(configPath).good()) throw std::runtime_error("Cannot open H2O model configuration");
    auto candidate = std::make_unique<Runtime>();
    candidate->model.reset(Llm::createLLM(configPath));
    if (!candidate->model) throw std::runtime_error("Cannot create H2O model");
    const std::string config = "{\"backend_type\":\"cpu\",\"thread_num\":" + std::to_string(threads) +
        ",\"precision\":\"normal\",\"memory\":\"low\",\"dynamic_option\":2,"
        "\"mllm\":{\"backend_type\":\"cpu\",\"thread_num\":" + std::to_string(threads) +
        ",\"precision\":\"normal\",\"memory\":\"low\"}}";
    if (!candidate->model->set_config(config) || !candidate->model->load()) {
        throw std::runtime_error("Cannot load H2O model");
    }
    if (candidate->model->cpu_thread_count() != threads) {
        throw std::runtime_error("H2O CPU runtime does not match the requested thread count");
    }
    static const std::regex visualFlag("\"is_visual\"\\s*:\\s*true");
    candidate->supportsImages = std::regex_search(candidate->model->dump_config(), visualFlag);
    for (size_t index = 0; index < labels().size(); ++index) {
        const auto tokens = candidate->model->tokenizer_encode(" " + labels()[index]);
        if (tokens.size() != 1 || tokens[0] != Contract::labelTokens[index]) {
            throw std::runtime_error("Tokenizer does not match the H2O label contract");
        }
        candidate->labelTokens.push_back(tokens[0]);
    }
    candidate->maxInputTokens = maxInputTokens;
    runtime_ = std::move(candidate);
}

DecisionResult DecisionModel::decide(const Question& question, const Image* image) {
    const auto prepared = prepareQuestion(question, image != nullptr);
    if (image && (image->width < 1 || image->height < 1 ||
        static_cast<size_t>(image->width) > std::numeric_limits<size_t>::max() / 3 / image->height ||
        image->rgb.size() != static_cast<size_t>(image->width) * image->height * 3)) {
        throw std::invalid_argument("Image must contain width * height * 3 packed RGB bytes");
    }
    std::lock_guard<std::mutex> lock(mutex_);
    if (!runtime_) throw std::runtime_error("Load the H2O model before inference");
    if (image && !runtime_->supportsImages) throw std::invalid_argument("Loaded H2O model has no visual encoder");
    auto& model = runtime_->model;
    try {
        model->reset();
        model->generate_init(nullptr, nullptr);
        const auto start = Clock::now();
        MNN::Transformer::MultimodalPrompt prompt;
        prompt.prompt_template = prepared.prompt;
        if (image) {
            auto tensor = MNN::Express::_Input({image->height, image->width, 3},
                MNN::Express::NHWC, halide_type_of<uint8_t>());
            auto* pixels = tensor->writeMap<uint8_t>();
            if (!pixels) throw std::runtime_error("Cannot allocate image tensor");
            // Omni's in-memory image path expects BGR, the public wrapper accepts RGB.
            for (size_t index = 0; index < image->rgb.size(); index += 3) {
                pixels[index] = image->rgb[index + 2];
                pixels[index + 1] = image->rgb[index + 1];
                pixels[index + 2] = image->rgb[index];
            }
            MNN::Transformer::PromptImagePart part;
            part.image_data = tensor;
            part.width = 0;
            part.height = 0;
            prompt.images["image_0"] = part;
        }
        const auto tokens = model->tokenizer_encode(prompt);
        if (tokens.empty() || tokens.size() > static_cast<size_t>(runtime_->maxInputTokens)) {
            throw std::invalid_argument("H2O input is empty or exceeds the token limit");
        }
        const double preprocessingMs = elapsedMs(start);
        const auto forwardStart = Clock::now();
        auto logits = model->forward(tokens);
        if (!logits.get() || !logits->getInfo()) throw std::runtime_error("Missing H2O logits");
        const auto* values = logits->readMap<float>();
        if (!values) throw std::runtime_error("Cannot read H2O logits");
        std::vector<float> candidates;
        for (size_t index = 0; index < prepared.options.size(); ++index) {
            const int token = runtime_->labelTokens[index];
            if (token < 0 || token >= logits->getInfo()->size) {
                throw std::runtime_error("Candidate token exceeds H2O output vocabulary");
            }
            candidates.push_back(values[token]);
        }
        const double forwardMs = elapsedMs(forwardStart);
        auto result = readDecision(prepared, candidates);
        result.inputTokens = static_cast<int>(tokens.size());
        result.cpuThreads = model->cpu_thread_count();
        result.preprocessingMs = preprocessingMs;
        result.forwardMs = forwardMs;
        return result;
    } catch (...) {
        // Discard partial caches after a failed forward before accepting another question.
        model->reset();
        throw;
    }
}

int DecisionModel::cpuThreadCount() const {
    std::lock_guard<std::mutex> lock(mutex_);
    return runtime_ ? runtime_->model->cpu_thread_count() : 0;
}

void DecisionModel::release() {
    std::lock_guard<std::mutex> lock(mutex_);
    runtime_.reset();
}

bool DecisionModel::isLoaded() const {
    std::lock_guard<std::mutex> lock(mutex_);
    return runtime_ != nullptr;
}

} // namespace H2o
