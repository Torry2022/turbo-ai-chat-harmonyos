#include "gemma_runner.h"

#include <algorithm>
#include <cstdint>
#include <string>
#include <vector>
#include <memory>

#include "napi/native_api.h"

namespace {

GemmaRunner g_runner;

struct StreamChunk {
    std::string value;
};

struct StreamWork {
    napi_env env = nullptr;
    napi_async_work work = nullptr;
    napi_deferred deferred = nullptr;
    napi_threadsafe_function callback = nullptr;
    std::string prompt;
    std::string endWith;
    std::vector<GemmaRunner::ChatTurn> chatMessages;
    bool useChatMessages = false;
    bool useImage = false;
    GemmaRunner::ImageData image;
    GemmaRunner::SamplingConfig sampling;
    GemmaRunner::GenerationResult output;
    std::string error;
};

struct AsyncGenerateWork {
    napi_env env = nullptr;
    napi_async_work work = nullptr;
    napi_deferred deferred = nullptr;
    std::string prompt;
    GemmaRunner::SamplingConfig sampling;
    std::string output;
    std::string error;
};

struct AsyncLoadWork {
    napi_env env = nullptr;
    napi_async_work work = nullptr;
    napi_deferred deferred = nullptr;
    std::string configPath;
    int32_t threadNum = 4;
    GemmaRunner::SamplingConfig sampling;
    std::string error;
};

std::string ReadString(napi_env env, napi_value value) {
    size_t length = 0;
    napi_get_value_string_utf8(env, value, nullptr, 0, &length);
    std::vector<char> buffer(length + 1);
    napi_get_value_string_utf8(env, value, buffer.data(), buffer.size(), &length);
    return std::string(buffer.data(), length);
}

int32_t ReadOptionalInt(napi_env env, napi_value* args, size_t argc, size_t index, int32_t fallback) {
    if (index >= argc || args[index] == nullptr) {
        return fallback;
    }

    napi_valuetype type = napi_undefined;
    napi_typeof(env, args[index], &type);
    if (type != napi_number) {
        return fallback;
    }

    int32_t value = fallback;
    napi_get_value_int32(env, args[index], &value);
    return value;
}

napi_value MakeString(napi_env env, const std::string& value) {
    napi_value result = nullptr;
    napi_create_string_utf8(env, value.c_str(), value.size(), &result);
    return result;
}

double ReadNamedDouble(napi_env env, napi_value object, const char* name, double fallback) {
    bool hasProperty = false;
    napi_has_named_property(env, object, name, &hasProperty);
    if (!hasProperty) {
        return fallback;
    }

    napi_value value = nullptr;
    napi_get_named_property(env, object, name, &value);
    if (value == nullptr) {
        return fallback;
    }

    napi_valuetype type = napi_undefined;
    napi_typeof(env, value, &type);
    if (type != napi_number) {
        return fallback;
    }

    double result = fallback;
    napi_get_value_double(env, value, &result);
    return result;
}

int32_t ReadNamedInt(napi_env env, napi_value object, const char* name, int32_t fallback) {
    bool hasProperty = false;
    napi_has_named_property(env, object, name, &hasProperty);
    if (!hasProperty) {
        return fallback;
    }

    napi_value value = nullptr;
    napi_get_named_property(env, object, name, &value);
    if (value == nullptr) {
        return fallback;
    }

    napi_valuetype type = napi_undefined;
    napi_typeof(env, value, &type);
    if (type != napi_number) {
        return fallback;
    }

    int32_t result = fallback;
    napi_get_value_int32(env, value, &result);
    return result;
}

GemmaRunner::SamplingConfig ReadSamplingConfig(
    napi_env env,
    napi_value* args,
    size_t argc,
    size_t maxTokensIndex,
    int32_t fallbackMaxTokens,
    size_t settingsIndex) {
    GemmaRunner::SamplingConfig sampling;
    sampling.maxNewTokens = std::clamp(
        ReadOptionalInt(env, args, argc, maxTokensIndex, fallbackMaxTokens),
        1,
        2048);

    if (settingsIndex >= argc || args[settingsIndex] == nullptr) {
        return sampling;
    }

    napi_valuetype type = napi_undefined;
    napi_typeof(env, args[settingsIndex], &type);
    if (type != napi_object) {
        return sampling;
    }

    sampling.temperature = std::clamp(ReadNamedDouble(env, args[settingsIndex], "temperature", sampling.temperature), 0.0, 2.0);
    sampling.topP = std::clamp(ReadNamedDouble(env, args[settingsIndex], "topP", sampling.topP), 0.05, 1.0);
    sampling.topP = std::clamp(ReadNamedDouble(env, args[settingsIndex], "top_p", sampling.topP), 0.05, 1.0);
    sampling.topK = std::clamp(ReadNamedInt(env, args[settingsIndex], "topK", sampling.topK), 1, 256);
    sampling.topK = std::clamp(ReadNamedInt(env, args[settingsIndex], "top_k", sampling.topK), 1, 256);
    sampling.repetitionPenalty = std::clamp(
        ReadNamedDouble(env, args[settingsIndex], "repetitionPenalty", sampling.repetitionPenalty),
        0.8,
        2.0);
    sampling.repetitionPenalty = std::clamp(
        ReadNamedDouble(env, args[settingsIndex], "repetition_penalty", sampling.repetitionPenalty),
        0.8,
        2.0);
    sampling.frequencyPenalty = std::clamp(
        ReadNamedDouble(env, args[settingsIndex], "frequencyPenalty", sampling.frequencyPenalty),
        0.0,
        2.0);
    sampling.presencePenalty = std::clamp(
        ReadNamedDouble(env, args[settingsIndex], "presencePenalty", sampling.presencePenalty),
        0.0,
        2.0);
    sampling.penaltyWindow = std::clamp(
        ReadNamedInt(env, args[settingsIndex], "penaltyWindow", sampling.penaltyWindow),
        64,
        2048);
    return sampling;
}

napi_value MakeGenerationResult(napi_env env, const GemmaRunner::GenerationResult& value) {
    napi_value result = nullptr;
    napi_create_object(env, &result);

    napi_value text = MakeString(env, value.text);
    napi_set_named_property(env, result, "text", text);

    napi_value generatedTokens = nullptr;
    napi_create_int32(env, value.generatedTokens, &generatedTokens);
    napi_set_named_property(env, result, "generatedTokens", generatedTokens);

    napi_value stopReason = MakeString(env, value.stopReason);
    napi_set_named_property(env, result, "stopReason", stopReason);

    return result;
}

bool ReadChatMessages(napi_env env, napi_value value, std::vector<GemmaRunner::ChatTurn>& messages, std::string& error) {
    bool isArray = false;
    napi_is_array(env, value, &isArray);
    if (!isArray) {
        error = "chat messages must be an array";
        return false;
    }

    uint32_t length = 0;
    napi_get_array_length(env, value, &length);
    messages.clear();
    messages.reserve(length);

    for (uint32_t i = 0; i < length; ++i) {
        napi_value item = nullptr;
        napi_get_element(env, value, i, &item);
        if (item == nullptr) {
            continue;
        }

        bool hasRole = false;
        bool hasContent = false;
        napi_has_named_property(env, item, "role", &hasRole);
        napi_has_named_property(env, item, "content", &hasContent);
        if (!hasRole || !hasContent) {
            error = "each chat message must have role and content";
            return false;
        }

        napi_value roleValue = nullptr;
        napi_value contentValue = nullptr;
        napi_get_named_property(env, item, "role", &roleValue);
        napi_get_named_property(env, item, "content", &contentValue);

        napi_valuetype roleType = napi_undefined;
        napi_valuetype contentType = napi_undefined;
        napi_typeof(env, roleValue, &roleType);
        napi_typeof(env, contentValue, &contentType);
        if (roleType != napi_string || contentType != napi_string) {
            error = "each chat message must have string role and content";
            return false;
        }

        std::string role = ReadString(env, roleValue);
        std::string content = ReadString(env, contentValue);
        if (!role.empty() && !content.empty()) {
            messages.push_back({role, content});
        }
    }

    if (messages.empty()) {
        error = "chat messages are empty";
        return false;
    }
    return true;
}

bool ReadRgbaImage(
    napi_env env,
    napi_value bufferValue,
    int32_t width,
    int32_t height,
    GemmaRunner::ImageData& image,
    std::string& error) {
    if (width <= 0 || height <= 0) {
        error = "image width and height must be positive";
        return false;
    }

    bool isArrayBuffer = false;
    napi_is_arraybuffer(env, bufferValue, &isArrayBuffer);
    if (!isArrayBuffer) {
        error = "image payload must be an ArrayBuffer";
        return false;
    }

    void* data = nullptr;
    size_t byteLength = 0;
    napi_get_arraybuffer_info(env, bufferValue, &data, &byteLength);
    const size_t pixelCount = static_cast<size_t>(width) * static_cast<size_t>(height);
    const size_t expectedRgbaBytes = pixelCount * 4;
    if (data == nullptr || byteLength < expectedRgbaBytes) {
        error = "image ArrayBuffer is smaller than width * height * 4";
        return false;
    }

    const auto* rgba = static_cast<const uint8_t*>(data);
    image.width = width;
    image.height = height;
    image.rgb.resize(pixelCount * 3);
    for (size_t i = 0; i < pixelCount; ++i) {
        image.rgb[i * 3] = rgba[i * 4 + 2];
        image.rgb[i * 3 + 1] = rgba[i * 4 + 1];
        image.rgb[i * 3 + 2] = rgba[i * 4];
    }
    return true;
}

napi_value LoadModel(napi_env env, napi_callback_info info) {
    size_t argc = 4;
    napi_value args[4] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    if (argc < 1 || args[0] == nullptr) {
        napi_throw_error(env, nullptr, "loadModel requires a config.json path");
        return nullptr;
    }

    std::string configPath = ReadString(env, args[0]);
    int32_t threadNum = std::clamp(ReadOptionalInt(env, args, argc, 1, 4), 1, 8);
    GemmaRunner::SamplingConfig sampling = ReadSamplingConfig(env, args, argc, 2, 128, 3);

    std::string error;
    if (!g_runner.load(configPath, threadNum, sampling, error)) {
        napi_throw_error(env, nullptr, error.c_str());
        return nullptr;
    }

    return MakeString(env, "loaded: " + configPath);
}

napi_value LoadModelAsync(napi_env env, napi_callback_info info) {
    size_t argc = 4;
    napi_value args[4] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    if (argc < 1 || args[0] == nullptr) {
        napi_throw_error(env, nullptr, "loadModelAsync requires a config.json path");
        return nullptr;
    }

    auto* work = new AsyncLoadWork();
    work->env = env;
    work->configPath = ReadString(env, args[0]);
    work->threadNum = std::clamp(ReadOptionalInt(env, args, argc, 1, 4), 1, 8);
    work->sampling = ReadSamplingConfig(env, args, argc, 2, 128, 3);

    napi_value promise = nullptr;
    napi_create_promise(env, &work->deferred, &promise);

    napi_value resourceName = nullptr;
    napi_create_string_utf8(env, "gemmaLoadModelAsync", NAPI_AUTO_LENGTH, &resourceName);
    napi_create_async_work(
        env,
        nullptr,
        resourceName,
        [](napi_env, void* data) {
            auto* work = static_cast<AsyncLoadWork*>(data);
            if (!g_runner.load(work->configPath, work->threadNum, work->sampling, work->error)) {
                return;
            }
        },
        [](napi_env env, napi_status, void* data) {
            auto* work = static_cast<AsyncLoadWork*>(data);
            if (!work->error.empty()) {
                napi_value err = MakeString(env, work->error);
                napi_reject_deferred(env, work->deferred, err);
            } else {
                napi_value result = MakeString(env, "loaded: " + work->configPath);
                napi_resolve_deferred(env, work->deferred, result);
            }
            napi_delete_async_work(env, work->work);
            delete work;
        },
        work,
        &work->work);

    napi_queue_async_work(env, work->work);
    return promise;
}

napi_value Generate(napi_env env, napi_callback_info info) {
    size_t argc = 3;
    napi_value args[3] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    if (argc < 1 || args[0] == nullptr) {
        napi_throw_error(env, nullptr, "generate requires a prompt");
        return nullptr;
    }

    std::string prompt = ReadString(env, args[0]);
    GemmaRunner::SamplingConfig sampling = ReadSamplingConfig(env, args, argc, 1, 128, 2);

    std::string error;
    std::string output = g_runner.generate(prompt, sampling, error);
    if (!error.empty()) {
        napi_throw_error(env, nullptr, error.c_str());
        return nullptr;
    }

    return MakeString(env, output);
}

napi_value GenerateAsync(napi_env env, napi_callback_info info) {
    size_t argc = 3;
    napi_value args[3] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    if (argc < 1 || args[0] == nullptr) {
        napi_throw_error(env, nullptr, "generateAsync requires a prompt");
        return nullptr;
    }

    auto* work = new AsyncGenerateWork();
    work->env = env;
    work->prompt = ReadString(env, args[0]);
    work->sampling = ReadSamplingConfig(env, args, argc, 1, 64, 2);

    napi_value promise = nullptr;
    napi_create_promise(env, &work->deferred, &promise);

    napi_value resourceName = nullptr;
    napi_create_string_utf8(env, "gemmaGenerateAsync", NAPI_AUTO_LENGTH, &resourceName);
    napi_create_async_work(
        env,
        nullptr,
        resourceName,
        [](napi_env, void* data) {
            auto* work = static_cast<AsyncGenerateWork*>(data);
            work->output = g_runner.generate(work->prompt, work->sampling, work->error);
        },
        [](napi_env env, napi_status, void* data) {
            auto* work = static_cast<AsyncGenerateWork*>(data);
            if (!work->error.empty()) {
                napi_value err = MakeString(env, work->error);
                napi_reject_deferred(env, work->deferred, err);
            } else {
                napi_value result = MakeString(env, work->output);
                napi_resolve_deferred(env, work->deferred, result);
            }
            napi_delete_async_work(env, work->work);
            delete work;
        },
        work,
        &work->work);

    napi_queue_async_work(env, work->work);
    return promise;
}

void CallStreamChunk(napi_env env, napi_value jsCallback, void*, void* data) {
    std::unique_ptr<StreamChunk> chunk(static_cast<StreamChunk*>(data));
    if (env == nullptr || jsCallback == nullptr || chunk == nullptr) {
        return;
    }

    napi_value global = nullptr;
    napi_get_global(env, &global);

    napi_value argv[1] = {nullptr};
    napi_create_string_utf8(env, chunk->value.c_str(), chunk->value.size(), &argv[0]);

    napi_value result = nullptr;
    napi_call_function(env, global, jsCallback, 1, argv, &result);
}

napi_value GenerateStream(napi_env env, napi_callback_info info) {
    size_t argc = 4;
    napi_value args[4] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    if (argc < 1 || args[0] == nullptr) {
        napi_throw_error(env, nullptr, "generateStream requires a prompt");
        return nullptr;
    }
    size_t callbackIndex = argc >= 4 && args[3] != nullptr ? 3 : 2;
    if (argc <= callbackIndex || args[callbackIndex] == nullptr) {
        napi_throw_error(env, nullptr, "generateStream requires an onChunk callback");
        return nullptr;
    }

    napi_valuetype callbackType = napi_undefined;
    napi_typeof(env, args[callbackIndex], &callbackType);
    if (callbackType != napi_function) {
        napi_throw_error(env, nullptr, "generateStream onChunk must be a function");
        return nullptr;
    }

    auto* streamWork = new StreamWork();
    streamWork->env = env;
    streamWork->prompt = ReadString(env, args[0]);
    streamWork->sampling = ReadSamplingConfig(env, args, argc, 1, 64, callbackIndex == 3 ? 2 : argc);

    napi_value promise = nullptr;
    napi_create_promise(env, &streamWork->deferred, &promise);

    napi_value resourceName = nullptr;
    napi_create_string_utf8(env, "gemmaGenerateStream", NAPI_AUTO_LENGTH, &resourceName);
    napi_status tsfnStatus = napi_create_threadsafe_function(
        env,
        args[callbackIndex],
        nullptr,
        resourceName,
        0,
        1,
        nullptr,
        nullptr,
        nullptr,
        CallStreamChunk,
        &streamWork->callback);

    if (tsfnStatus != napi_ok) {
        delete streamWork;
        napi_throw_error(env, nullptr, "generateStream failed to create threadsafe function");
        return nullptr;
    }

    napi_create_async_work(
        env,
        nullptr,
        resourceName,
        [](napi_env, void* data) {
            auto* work = static_cast<StreamWork*>(data);
            work->output = g_runner.generateStreaming(
                work->prompt,
                work->sampling,
                [work](const std::string& chunk) {
                    if (chunk.empty()) {
                        return;
                    }
                    auto* streamChunk = new StreamChunk{chunk};
                    napi_call_threadsafe_function(work->callback, streamChunk, napi_tsfn_nonblocking);
                },
                work->error);
        },
        [](napi_env env, napi_status, void* data) {
            auto* work = static_cast<StreamWork*>(data);
            if (!work->error.empty()) {
                napi_value err = MakeString(env, work->error);
                napi_reject_deferred(env, work->deferred, err);
            } else {
                napi_value result = MakeGenerationResult(env, work->output);
                napi_resolve_deferred(env, work->deferred, result);
            }
            napi_release_threadsafe_function(work->callback, napi_tsfn_release);
            napi_delete_async_work(env, work->work);
            delete work;
        },
        streamWork,
        &streamWork->work);

    napi_queue_async_work(env, streamWork->work);
    return promise;
}

napi_value GenerateRawPromptStream(napi_env env, napi_callback_info info) {
    size_t argc = 5;
    napi_value args[5] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    if (argc < 1 || args[0] == nullptr) {
        napi_throw_error(env, nullptr, "generateRawPromptStream requires a prompt");
        return nullptr;
    }
    size_t callbackIndex = argc >= 5 && args[4] != nullptr ? 4 : 3;
    if (argc <= callbackIndex || args[callbackIndex] == nullptr) {
        napi_throw_error(env, nullptr, "generateRawPromptStream requires an onChunk callback");
        return nullptr;
    }

    napi_valuetype callbackType = napi_undefined;
    napi_typeof(env, args[callbackIndex], &callbackType);
    if (callbackType != napi_function) {
        napi_throw_error(env, nullptr, "generateRawPromptStream onChunk must be a function");
        return nullptr;
    }

    auto* streamWork = new StreamWork();
    streamWork->env = env;
    streamWork->prompt = ReadString(env, args[0]);
    streamWork->sampling = ReadSamplingConfig(env, args, argc, 1, 64, callbackIndex == 4 ? 3 : argc);
    if (argc >= 3 && args[2] != nullptr) {
        napi_valuetype endWithType = napi_undefined;
        napi_typeof(env, args[2], &endWithType);
        if (endWithType == napi_string) {
            streamWork->endWith = ReadString(env, args[2]);
        }
    }

    napi_value promise = nullptr;
    napi_create_promise(env, &streamWork->deferred, &promise);

    napi_value resourceName = nullptr;
    napi_create_string_utf8(env, "gemmaGenerateRawPromptStream", NAPI_AUTO_LENGTH, &resourceName);
    napi_status tsfnStatus = napi_create_threadsafe_function(
        env,
        args[callbackIndex],
        nullptr,
        resourceName,
        0,
        1,
        nullptr,
        nullptr,
        nullptr,
        CallStreamChunk,
        &streamWork->callback);

    if (tsfnStatus != napi_ok) {
        delete streamWork;
        napi_throw_error(env, nullptr, "generateRawPromptStream failed to create threadsafe function");
        return nullptr;
    }

    napi_create_async_work(
        env,
        nullptr,
        resourceName,
        [](napi_env, void* data) {
            auto* work = static_cast<StreamWork*>(data);
            work->output = g_runner.generateRawPromptStreaming(
                work->prompt,
                work->sampling,
                work->endWith,
                [work](const std::string& chunk) {
                    if (chunk.empty()) {
                        return;
                    }
                    auto* streamChunk = new StreamChunk{chunk};
                    napi_call_threadsafe_function(work->callback, streamChunk, napi_tsfn_nonblocking);
                },
                work->error);
        },
        [](napi_env env, napi_status, void* data) {
            auto* work = static_cast<StreamWork*>(data);
            if (!work->error.empty()) {
                napi_value err = MakeString(env, work->error);
                napi_reject_deferred(env, work->deferred, err);
            } else {
                napi_value result = MakeGenerationResult(env, work->output);
                napi_resolve_deferred(env, work->deferred, result);
            }
            napi_release_threadsafe_function(work->callback, napi_tsfn_release);
            napi_delete_async_work(env, work->work);
            delete work;
        },
        streamWork,
        &streamWork->work);

    napi_queue_async_work(env, streamWork->work);
    return promise;
}

napi_value GenerateChatStream(napi_env env, napi_callback_info info) {
    size_t argc = 4;
    napi_value args[4] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    if (argc < 1 || args[0] == nullptr) {
        napi_throw_error(env, nullptr, "generateChatStream requires chat messages");
        return nullptr;
    }
    size_t callbackIndex = argc >= 4 && args[3] != nullptr ? 3 : 2;
    if (argc <= callbackIndex || args[callbackIndex] == nullptr) {
        napi_throw_error(env, nullptr, "generateChatStream requires an onChunk callback");
        return nullptr;
    }

    napi_valuetype callbackType = napi_undefined;
    napi_typeof(env, args[callbackIndex], &callbackType);
    if (callbackType != napi_function) {
        napi_throw_error(env, nullptr, "generateChatStream onChunk must be a function");
        return nullptr;
    }

    auto* streamWork = new StreamWork();
    streamWork->env = env;
    streamWork->useChatMessages = true;
    streamWork->sampling = ReadSamplingConfig(env, args, argc, 1, 64, callbackIndex == 3 ? 2 : argc);

    std::string readError;
    if (!ReadChatMessages(env, args[0], streamWork->chatMessages, readError)) {
        delete streamWork;
        napi_throw_error(env, nullptr, readError.c_str());
        return nullptr;
    }

    napi_value promise = nullptr;
    napi_create_promise(env, &streamWork->deferred, &promise);

    napi_value resourceName = nullptr;
    napi_create_string_utf8(env, "gemmaGenerateChatStream", NAPI_AUTO_LENGTH, &resourceName);
    napi_create_threadsafe_function(
        env,
        args[callbackIndex],
        nullptr,
        resourceName,
        0,
        1,
        nullptr,
        nullptr,
        nullptr,
        CallStreamChunk,
        &streamWork->callback);

    napi_create_async_work(
        env,
        nullptr,
        resourceName,
        [](napi_env, void* data) {
            auto* work = static_cast<StreamWork*>(data);
            work->output = g_runner.generateChatStreaming(
                work->chatMessages,
                work->sampling,
                [work](const std::string& chunk) {
                    if (chunk.empty()) {
                        return;
                    }
                    auto* streamChunk = new StreamChunk{chunk};
                    napi_call_threadsafe_function(work->callback, streamChunk, napi_tsfn_nonblocking);
                },
                work->error);
        },
        [](napi_env env, napi_status, void* data) {
            auto* work = static_cast<StreamWork*>(data);
            if (!work->error.empty()) {
                napi_value err = MakeString(env, work->error);
                napi_reject_deferred(env, work->deferred, err);
            } else {
                napi_value result = MakeGenerationResult(env, work->output);
                napi_resolve_deferred(env, work->deferred, result);
            }
            napi_release_threadsafe_function(work->callback, napi_tsfn_release);
            napi_delete_async_work(env, work->work);
            delete work;
        },
        streamWork,
        &streamWork->work);

    napi_queue_async_work(env, streamWork->work);
    return promise;
}

napi_value GenerateImageChatStream(napi_env env, napi_callback_info info) {
    size_t argc = 7;
    napi_value args[7] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    if (argc < 1 || args[0] == nullptr) {
        napi_throw_error(env, nullptr, "generateImageChatStream requires chat messages");
        return nullptr;
    }
    if (argc < 4 || args[1] == nullptr || args[2] == nullptr || args[3] == nullptr) {
        napi_throw_error(env, nullptr, "generateImageChatStream requires image buffer, width and height");
        return nullptr;
    }
    size_t callbackIndex = argc >= 7 && args[6] != nullptr ? 6 : 5;
    if (argc <= callbackIndex || args[callbackIndex] == nullptr) {
        napi_throw_error(env, nullptr, "generateImageChatStream requires an onChunk callback");
        return nullptr;
    }

    napi_valuetype callbackType = napi_undefined;
    napi_typeof(env, args[callbackIndex], &callbackType);
    if (callbackType != napi_function) {
        napi_throw_error(env, nullptr, "generateImageChatStream onChunk must be a function");
        return nullptr;
    }

    auto* streamWork = new StreamWork();
    streamWork->env = env;
    streamWork->useChatMessages = true;
    streamWork->useImage = true;
    streamWork->sampling = ReadSamplingConfig(env, args, argc, 4, 64, callbackIndex == 6 ? 5 : argc);

    std::string readError;
    if (!ReadChatMessages(env, args[0], streamWork->chatMessages, readError)) {
        delete streamWork;
        napi_throw_error(env, nullptr, readError.c_str());
        return nullptr;
    }

    int32_t width = 0;
    int32_t height = 0;
    napi_get_value_int32(env, args[2], &width);
    napi_get_value_int32(env, args[3], &height);
    if (!ReadRgbaImage(env, args[1], width, height, streamWork->image, readError)) {
        delete streamWork;
        napi_throw_error(env, nullptr, readError.c_str());
        return nullptr;
    }

    napi_value promise = nullptr;
    napi_create_promise(env, &streamWork->deferred, &promise);

    napi_value resourceName = nullptr;
    napi_create_string_utf8(env, "gemmaGenerateImageChatStream", NAPI_AUTO_LENGTH, &resourceName);
    napi_create_threadsafe_function(
        env,
        args[callbackIndex],
        nullptr,
        resourceName,
        0,
        1,
        nullptr,
        nullptr,
        nullptr,
        CallStreamChunk,
        &streamWork->callback);

    napi_create_async_work(
        env,
        nullptr,
        resourceName,
        [](napi_env, void* data) {
            auto* work = static_cast<StreamWork*>(data);
            work->output = g_runner.generateImageChatStreaming(
                work->chatMessages,
                work->image,
                work->sampling,
                [work](const std::string& chunk) {
                    if (chunk.empty()) {
                        return;
                    }
                    auto* streamChunk = new StreamChunk{chunk};
                    napi_call_threadsafe_function(work->callback, streamChunk, napi_tsfn_nonblocking);
                },
                work->error);
        },
        [](napi_env env, napi_status, void* data) {
            auto* work = static_cast<StreamWork*>(data);
            if (!work->error.empty()) {
                napi_value err = MakeString(env, work->error);
                napi_reject_deferred(env, work->deferred, err);
            } else {
                napi_value result = MakeGenerationResult(env, work->output);
                napi_resolve_deferred(env, work->deferred, result);
            }
            napi_release_threadsafe_function(work->callback, napi_tsfn_release);
            napi_delete_async_work(env, work->work);
            delete work;
        },
        streamWork,
        &streamWork->work);

    napi_queue_async_work(env, streamWork->work);
    return promise;
}

napi_value Reset(napi_env env, napi_callback_info info) {
    g_runner.reset();
    napi_value result = nullptr;
    napi_get_undefined(env, &result);
    return result;
}

napi_value IsLoaded(napi_env env, napi_callback_info info) {
    napi_value result = nullptr;
    napi_get_boolean(env, g_runner.isLoaded(), &result);
    return result;
}

static napi_value Init(napi_env env, napi_value exports) {
    napi_property_descriptor desc[] = {
        {"loadModel", nullptr, LoadModel, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"loadModelAsync", nullptr, LoadModelAsync, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"generate", nullptr, Generate, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"generateAsync", nullptr, GenerateAsync, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"generateStream", nullptr, GenerateStream, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"generateRawPromptStream", nullptr, GenerateRawPromptStream, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"generateChatStream", nullptr, GenerateChatStream, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"generateImageChatStream", nullptr, GenerateImageChatStream, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"reset", nullptr, Reset, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"isLoaded", nullptr, IsLoaded, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}

static napi_module entryModule = {
    1,
    0,
    nullptr,
    Init,
    "entry",
    nullptr,
    {0},
};

} // namespace

extern "C" __attribute__((constructor)) void RegisterGemma4MnnModule() {
    napi_module_register(&entryModule);
}
