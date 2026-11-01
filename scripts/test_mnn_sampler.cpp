// Compile with the pinned MNN sampler.cpp and --gc-sections. No model weights
// are needed: drive its real probability/penalty pipeline with synthetic logits.
#include "llmconfig.hpp"
#include "llm/llm.hpp"
#include <MNN/expr/MathOp.hpp>
#include <MNN/expr/NeuralNetWorkOp.hpp>
#include <random>
#include <functional>
#define private public
#include "sampler.hpp"
#undef private
#include "../entry/src/main/cpp/mnn_llm_runner.cpp"
#include <cmath>
#include <iostream>
#include <stdexcept>

using namespace MNN::Transformer;
void check(bool value) { if (!value) throw std::runtime_error("Sampler regression"); }
int main() {
    auto context = std::make_shared<LlmContext>();
    auto config = std::make_shared<LlmConfig>();
    config->config_ = ujson::json::parse(R"({"sampler_type":"mixed","mixed_samplers":["penalty","topK","topP","temperature"],"temperature":0.7,"top_k":3,"top_p":0.9,"repetition_penalty":1.05,"presence_penalty":0,"frequency_penalty":0,"penalty_window":256})");
    Sampler sampler(context, config);
    auto rng = sampler.mRng;
    config->config_.merge(ujson::json::parse(R"({"temperature":1.5,"top_k":2,"top_p":0.5,"repetition_penalty":1.4,"presence_penalty":0.3,"frequency_penalty":0.2,"penalty_window":64})"));
    sampler.reconfigure(config);
    check(sampler.mRng == rng);
    check(sampler.mConfig.temperature == 1.5f && sampler.mConfig.topK == 2 && sampler.mConfig.topP == .5f);
    check(sampler.mConfig.repetition_penalty == 1.4f && sampler.mConfig.presence_penalty == .3f);
    check(sampler.mConfig.frequency_penalty == .2f && sampler.mConfig.penalty_window == 64);
    const auto steps = sampler.mPipeline.size();
    for (int i = 0; i < 50; ++i) sampler.reconfigure(config);
    check(sampler.mPipeline.size() == steps); // No accumulating callbacks.

    // Temperature zero applies penalties, then chooses the best logit without
    // computing probabilities. The repeated token would otherwise win.
    MnnLlmRunner::SamplingConfig request;
    request.temperature = 0;
    request.repetitionPenalty = 1.5;
    request.presencePenalty = 1;
    request.frequencyPenalty = 1;
    request.penaltyWindow = 0;
    config->config_.merge(ujson::json::parse(BuildGenerationConfig(request)));
    sampler.reconfigure(config);
    context->history_tokens = {0, 0};
    SamplerState greedy;
    greedy.logits = {3.f, 2.f, 1.f};
    for (auto& step : sampler.mPipeline) step(greedy);
    check(greedy.selected_token == 1 && greedy.probs.empty());
    for (float value : greedy.logits) check(std::isfinite(value));

    // Zero window uses all history; a one-token window excludes the old token.
    context->history_tokens = {0, 1};
    config->config_.merge(ujson::json::parse(R"({"temperature":1,"repetition_penalty":1,"presence_penalty":1,"frequency_penalty":0,"penalty_window":1})"));
    sampler.reconfigure(config);
    SamplerState recent; recent.logits = {3.f, 3.f}; sampler.stepPenalty(recent);
    check(recent.logits[0] == 3.f && recent.logits[1] == 2.f);
    config->config_.merge(ujson::json::parse(R"({"penalty_window":0})"));
    sampler.reconfigure(config);
    SamplerState all; all.logits = {3.f, 3.f}; sampler.stepPenalty(all);
    check(all.logits[0] == 2.f && all.logits[1] == 2.f);

    // Returning from a low-temperature/title request must restore all settings.
    request = MnnLlmRunner::SamplingConfig{};
    request.temperature = .7;
    config->config_.merge(ujson::json::parse(BuildGenerationConfig(request)));
    sampler.reconfigure(config);
    check(sampler.mConfig.select_type == "temperature" && sampler.mConfig.topK == 40);
    check(sampler.mConfig.presence_penalty == 0 && sampler.mConfig.penalty_window == 256);
    std::cout << "PASS live sampler refresh, zero temperature, penalties, windows and restoration\n";
}
