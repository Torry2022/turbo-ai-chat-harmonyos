#include "laya_decision.h"
#include "laya_tokenizer.h"

#include <MNN/Interpreter.hpp>
#include <MNN/Tensor.hpp>

#include <algorithm>
#include <chrono>
#include <memory>
#include <mutex>
#include <sstream>
#include <stdexcept>

namespace {

struct LayaRuntime {
    std::string modelPath;
    std::string tokenizerPath;
    std::unique_ptr<LayaTokenizer> tokenizer;
    std::unique_ptr<MNN::Interpreter> interpreter;
    MNN::Session* session = nullptr;

    LayaRuntime(const std::string& model, const std::string& tokens) : modelPath(model), tokenizerPath(tokens) {}
    ~LayaRuntime() {
        if (session && interpreter) interpreter->releaseSession(session);
    }
};

std::mutex runtimeMutex;
std::unique_ptr<LayaRuntime> runtime;

std::string withoutMask(std::string value) {
    const std::string mask = "<mask>";
    for (size_t position = value.find(mask); position != std::string::npos; position = value.find(mask, position + 1)) {
        value.replace(position, mask.size(), " ");
    }
    return value;
}

void setInput(MNN::Interpreter& interpreter, MNN::Session* session, const char* name,
    const std::vector<int>& values) {
    MNN::Tensor* input = interpreter.getSessionInput(session, name);
    if (!input || input->elementSize() != values.size()) throw std::runtime_error(std::string("Invalid input: ") + name);
    MNN::Tensor host(input, MNN::Tensor::CAFFE);
    std::copy(values.begin(), values.end(), host.host<int32_t>());
    if (!input->copyFromHostTensor(&host)) throw std::runtime_error(std::string("Input copy failed: ") + name);
}

std::vector<float> getOutput(MNN::Interpreter& interpreter, MNN::Session* session, const char* name) {
    MNN::Tensor* output = interpreter.getSessionOutput(session, name);
    if (!output) throw std::runtime_error(std::string("Missing output: ") + name);
    MNN::Tensor host(output, MNN::Tensor::CAFFE);
    if (!output->copyToHostTensor(&host)) throw std::runtime_error(std::string("Output copy failed: ") + name);
    return {host.host<float>(), host.host<float>() + host.elementSize()};
}

void appendArray(std::ostringstream& stream, const std::vector<float>& values) {
    stream << '[';
    for (size_t index = 0; index < values.size(); ++index) {
        if (index > 0) stream << ',';
        stream << values[index];
    }
    stream << ']';
}

bool resizeInput(MNN::Interpreter& interpreter, MNN::Session* session, const char* name,
    const std::vector<int>& shape) {
    MNN::Tensor* input = interpreter.getSessionInput(session, name);
    if (!input) throw std::runtime_error(std::string("Missing input: ") + name);
    if (input->shape() == shape) return false;
    interpreter.resizeTensor(input, shape);
    return true;
}

} // namespace

void loadLayaDecision(const std::string& modelPath, const std::string& tokenizerPath) {
    std::lock_guard<std::mutex> lock(runtimeMutex);
    if (runtime) throw std::runtime_error("Release the loaded decision model first");
    auto candidate = std::make_unique<LayaRuntime>(modelPath, tokenizerPath);
    candidate->tokenizer = std::make_unique<LayaTokenizer>(tokenizerPath);
    candidate->interpreter.reset(MNN::Interpreter::createFromFile(modelPath.c_str()));
    if (!candidate->interpreter) throw std::runtime_error("Cannot load Laya model");
    MNN::ScheduleConfig config;
    config.type = MNN_FORWARD_CPU;
    config.numThread = 4;
    candidate->session = candidate->interpreter->createSession(config);
    if (!candidate->session) throw std::runtime_error("Cannot create Laya session");
    runtime = std::move(candidate);
}

void releaseLayaDecision() {
    std::lock_guard<std::mutex> lock(runtimeMutex);
    runtime.reset();
}

std::string runLayaDecision(const std::string& modelPath, const std::string& tokenizerPath,
    const std::string& state, const std::string& type, const std::string& instruction,
    const std::vector<std::string>& options) {
    if (state.empty() || instruction.empty() || options.empty() || options.size() > 20) {
        throw std::runtime_error("Invalid Laya question");
    }
    const int qtype = type == "choice" ? 0 : type == "score" ? 1 : type == "noul" ? 2 : -1;
    if (qtype < 0) throw std::runtime_error("Unknown Laya question type");
    std::lock_guard<std::mutex> lock(runtimeMutex);
    const auto start = std::chrono::steady_clock::now();
    if (!runtime || runtime->modelPath != modelPath || runtime->tokenizerPath != tokenizerPath) {
        throw std::runtime_error("Load the decision model before inference");
    }
    std::vector<int> head = runtime->tokenizer->encode(type + " question: " + withoutMask(instruction));
    std::vector<std::vector<int>> optionIds;
    int optionTokens = 0;
    for (const std::string& option : options) {
        std::vector<int> ids = {4};
        std::vector<int> textIds = runtime->tokenizer->encode(" " + withoutMask(option));
        ids.insert(ids.end(), textIds.begin(), textIds.begin() + std::min<size_t>(48, textIds.size()));
        optionTokens += static_cast<int>(ids.size());
        optionIds.push_back(std::move(ids));
    }
    int headBudget = 192 - optionTokens;
    if (headBudget < 16) {
        const int perOption = std::max(4, (192 - 16) / static_cast<int>(optionIds.size()));
        optionTokens = 0;
        for (auto& ids : optionIds) {
            ids.resize(std::min<int>(perOption, ids.size()));
            optionTokens += static_cast<int>(ids.size());
        }
        headBudget = 192 - optionTokens;
    }
    head.resize(std::min<int>(head.size(), std::max(8, headBudget)));
    std::vector<int> ids = {2};
    ids.insert(ids.end(), head.begin(), head.end());
    ids.push_back(1);
    std::vector<int> markers;
    for (const auto& option : optionIds) {
        markers.push_back(static_cast<int>(ids.size()));
        ids.insert(ids.end(), option.begin(), option.end());
    }
    ids.push_back(1);
    std::vector<int> stateIds = runtime->tokenizer->encode(withoutMask(state));
    const size_t room = ids.size() < 511 ? 511 - ids.size() : 0;
    ids.insert(ids.end(), stateIds.begin(), stateIds.begin() + std::min(room, stateIds.size()));
    ids.push_back(1);
    if (ids.size() > 512) ids.resize(512);
    const auto inputReady = std::chrono::steady_clock::now();

    if (!runtime->interpreter) runtime->interpreter.reset(MNN::Interpreter::createFromFile(modelPath.c_str()));
    if (!runtime->interpreter) throw std::runtime_error("Cannot load Laya model");
    const auto modelLoaded = std::chrono::steady_clock::now();
    if (!runtime->session) {
        MNN::ScheduleConfig config;
        config.type = MNN_FORWARD_CPU;
        config.numThread = 4;
        runtime->session = runtime->interpreter->createSession(config);
    }
    if (!runtime->session) throw std::runtime_error("Cannot create Laya session");
    bool resized = false;
    for (const auto& shape : std::vector<std::pair<const char*, std::vector<int>>>{
        {"input_ids", {1, static_cast<int>(ids.size())}},
        {"attention_mask", {1, static_cast<int>(ids.size())}},
        {"marker_pos", {1, static_cast<int>(markers.size())}},
        {"marker_mask", {1, static_cast<int>(markers.size())}},
        {"qtype", {1}}
    }) {
        resized = resizeInput(*runtime->interpreter, runtime->session, shape.first, shape.second) || resized;
    }
    if (resized) runtime->interpreter->resizeSession(runtime->session);
    setInput(*runtime->interpreter, runtime->session, "input_ids", ids);
    setInput(*runtime->interpreter, runtime->session, "attention_mask", std::vector<int>(ids.size(), 1));
    setInput(*runtime->interpreter, runtime->session, "marker_pos", markers);
    setInput(*runtime->interpreter, runtime->session, "marker_mask", std::vector<int>(markers.size(), 1));
    setInput(*runtime->interpreter, runtime->session, "qtype", {qtype});
    const auto sessionReady = std::chrono::steady_clock::now();
    if (runtime->interpreter->runSession(runtime->session) != MNN::NO_ERROR) throw std::runtime_error("Laya inference failed");
    const auto inferenceDone = std::chrono::steady_clock::now();
    const std::vector<float> logits = getOutput(*runtime->interpreter, runtime->session, "logits");
    const std::vector<float> act = getOutput(*runtime->interpreter, runtime->session, "act_probs");
    const auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::steady_clock::now() - start).count();
    std::ostringstream report;
    report << "{\"logits\":";
    appendArray(report, logits);
    report << ",\"act_probs\":";
    appendArray(report, act);
    report << ",\"elapsed_ms\":" << elapsed
           << ",\"input_ms\":" << std::chrono::duration_cast<std::chrono::milliseconds>(inputReady - start).count()
           << ",\"model_load_ms\":" << std::chrono::duration_cast<std::chrono::milliseconds>(modelLoaded - inputReady).count()
           << ",\"session_setup_ms\":" << std::chrono::duration_cast<std::chrono::milliseconds>(sessionReady - modelLoaded).count()
           << ",\"inference_ms\":" << std::chrono::duration_cast<std::chrono::milliseconds>(inferenceDone - sessionReady).count()
           << '}';
    return report.str();
}
