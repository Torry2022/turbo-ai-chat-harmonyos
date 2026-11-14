#include "h2o_napi.h"
#include "h2o_decision.h"
#include "mnn_cpu_capacity.h"
#include <algorithm>
#include <chrono>
#include <cmath>
#include <iomanip>
#include <limits>
#include <sstream>
#include <stdexcept>

namespace {
H2o::DecisionModel model;
enum class Operation { Load, Decide, Release };
struct Work {
    napi_async_work work = nullptr;
    napi_deferred deferred = nullptr;
    Operation operation;
    int threads = 4;
    std::string config, output, error;
    H2o::Question question;
    H2o::Image image;
};

std::string readString(napi_env env, napi_value value) {
    size_t size = 0;
    if (napi_get_value_string_utf8(env, value, nullptr, 0, &size) != napi_ok)
        throw std::invalid_argument("Expected text argument");
    std::vector<char> buffer(size + 1);
    napi_get_value_string_utf8(env, value, buffer.data(), buffer.size(), &size);
    return {buffer.data(), size};
}

std::vector<std::string> readStrings(napi_env env, napi_value value) {
    bool array = false;
    uint32_t size = 0;
    if (napi_is_array(env, value, &array) != napi_ok || !array ||
        napi_get_array_length(env, value, &size) != napi_ok || size > 255)
        throw std::invalid_argument("Expected up to 255 options");
    std::vector<std::string> result;
    for (uint32_t index = 0; index < size; ++index) {
        napi_value item;
        napi_get_element(env, value, index, &item);
        result.push_back(readString(env, item));
    }
    return result;
}

napi_value stringValue(napi_env env, const std::string& text) {
    napi_value value;
    napi_create_string_utf8(env, text.data(), text.size(), &value);
    return value;
}

napi_value queue(napi_env env, std::unique_ptr<Work> work) {
    napi_value promise;
    if (napi_create_promise(env, &work->deferred, &promise) != napi_ok) return nullptr;
    const auto status = napi_create_async_work(env, nullptr, stringValue(env, "h2oDecision"),
        [](napi_env, void* data) {
            auto& work = *static_cast<Work*>(data);
            try {
                if (work.operation == Operation::Load) {
                    PrepareMnnCpuCapacity();
                    model.load(work.config, work.threads);
                    work.output = "{\"cpu_threads\":" + std::to_string(model.cpuThreadCount()) + "}";
                } else if (work.operation == Operation::Release) {
                    model.release();
                } else {
                    const auto start = std::chrono::steady_clock::now();
                    auto result = model.decide(work.question, work.image.rgb.empty() ? nullptr : &work.image);
                    // The App's existing boolean contract orders false before true.
                    if (work.question.type == H2o::QuestionType::Noul) {
                        std::reverse(result.logits.begin(), result.logits.end());
                        std::reverse(result.probabilities.begin(), result.probabilities.end());
                    }
                    std::ostringstream output;
                    output << std::setprecision(std::numeric_limits<double>::max_digits10) << "{\"logits\":[";
                    for (size_t index = 0; index < result.logits.size(); ++index) {
                        if (index) output << ',';
                        output << result.logits[index];
                    }
                    output << "],\"probabilities\":[";
                    for (size_t index = 0; index < result.probabilities.size(); ++index) {
                        if (index) output << ',';
                        output << result.probabilities[index];
                    }
                    output << "],\"input_tokens\":" << result.inputTokens << ",\"cpu_threads\":" << result.cpuThreads << ",\"elapsed_ms\":"
                           << std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - start).count()
                           << '}';
                    work.output = output.str();
                }
            } catch (const std::exception& error) { work.error = error.what(); }
        },
        [](napi_env env, napi_status status, void* data) {
            std::unique_ptr<Work> work(static_cast<Work*>(data));
            if (status != napi_ok && work->error.empty()) work->error = "H2O operation cancelled";
            if (!work->error.empty()) napi_reject_deferred(env, work->deferred, stringValue(env, work->error));
            else napi_resolve_deferred(env, work->deferred, stringValue(env, work->output));
            napi_delete_async_work(env, work->work);
        }, work.get(), &work->work);
    if (status != napi_ok || napi_queue_async_work(env, work->work) != napi_ok) {
        if (work->work) napi_delete_async_work(env, work->work);
        napi_reject_deferred(env, work->deferred, stringValue(env, "Cannot schedule H2O operation"));
        return promise;
    }
    work.release();
    return promise;
}

napi_value load(napi_env env, napi_callback_info info) {
    size_t count = 2;
    napi_value args[2];
    napi_get_cb_info(env, info, &count, args, nullptr, nullptr);
    try {
        if (count < 1) throw std::invalid_argument("Expected H2O configuration path");
        auto work = std::make_unique<Work>();
        work->operation = Operation::Load;
        work->config = readString(env, args[0]);
        if (count > 1) {
            napi_valuetype type;
            napi_typeof(env, args[1], &type);
            if (type != napi_undefined) {
                double threads = 0;
                if (napi_get_value_double(env, args[1], &threads) != napi_ok ||
                    !std::isfinite(threads) || threads < 1 || threads > 16 || std::floor(threads) != threads)
                    throw std::invalid_argument("H2O threads must be an integer from 1 to 16");
                work->threads = static_cast<int>(threads);
            }
        }
        return queue(env, std::move(work));
    } catch (const std::exception& error) { napi_throw_type_error(env, nullptr, error.what()); return nullptr; }
}

napi_value decide(napi_env env, napi_callback_info info) {
    size_t count = 8;
    napi_value args[8];
    napi_get_cb_info(env, info, &count, args, nullptr, nullptr);
    try {
        if (count != 8) throw std::invalid_argument("Expected question, options and optional RGBA image");
        auto work = std::make_unique<Work>();
        work->operation = Operation::Decide;
        work->question.state = readString(env, args[0]);
        const auto type = readString(env, args[1]);
        work->question.type = type == "choice" ? H2o::QuestionType::Choice :
            type == "score" ? H2o::QuestionType::Score : H2o::QuestionType::Noul;
        if (type != "choice" && type != "score" && type != "noul") throw std::invalid_argument("Unknown decision type");
        work->question.instruction = readString(env, args[2]);
        const auto names = readStrings(env, args[3]);
        const auto descriptions = readStrings(env, args[4]);
        if (names.size() != descriptions.size()) throw std::invalid_argument("Option counts differ");
        if (type == "noul") {
            if (descriptions.size() != 2) throw std::invalid_argument("Boolean decisions require two options");
            work->question.options = {{"true", descriptions[1]}, {"false", descriptions[0]}};
        } else {
            for (size_t index = 0; index < names.size(); ++index)
                work->question.options.push_back({names[index], descriptions[index]});
        }
        void* pixels = nullptr;
        size_t bytes = 0;
        int32_t width = 0, height = 0;
        if (napi_get_arraybuffer_info(env, args[5], &pixels, &bytes) != napi_ok ||
            napi_get_value_int32(env, args[6], &width) != napi_ok || napi_get_value_int32(env, args[7], &height) != napi_ok)
            throw std::invalid_argument("Invalid image arguments");
        if (bytes > 0 || width != 0 || height != 0) {
            if (width < 1 || height < 1 ||
                bytes != static_cast<size_t>(width) * height * 4)
                throw std::invalid_argument("Invalid RGBA image dimensions");
            work->image.width = width;
            work->image.height = height;
            const auto* rgba = static_cast<const uint8_t*>(pixels);
            work->image.rgb.reserve(static_cast<size_t>(width) * height * 3);
            for (size_t index = 0; index < bytes; index += 4)
                work->image.rgb.insert(work->image.rgb.end(), rgba + index, rgba + index + 3);
        }
        return queue(env, std::move(work));
    } catch (const std::exception& error) { napi_throw_type_error(env, nullptr, error.what()); return nullptr; }
}

napi_value release(napi_env env, napi_callback_info) {
    auto work = std::make_unique<Work>();
    work->operation = Operation::Release;
    return queue(env, std::move(work));
}
}

void DefineH2oBindings(napi_env env, napi_value exports) {
    napi_property_descriptor properties[] = {
        {"h2oLoadAsync", nullptr, load, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"h2oDecideAsync", nullptr, decide, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"h2oReleaseAsync", nullptr, release, nullptr, nullptr, nullptr, napi_default, nullptr}
    };
    napi_define_properties(env, exports, 3, properties);
}
