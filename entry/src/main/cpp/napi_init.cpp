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
    std::vector<GemmaRunner::ChatTurn> chatMessages;
    bool useChatMessages = false;
    int32_t maxNewTokens = 64;
    std::string output;
    std::string error;
};

struct AsyncGenerateWork {
    napi_env env = nullptr;
    napi_async_work work = nullptr;
    napi_deferred deferred = nullptr;
    std::string prompt;
    int32_t maxNewTokens = 64;
    std::string output;
    std::string error;
};

struct AsyncLoadWork {
    napi_env env = nullptr;
    napi_async_work work = nullptr;
    napi_deferred deferred = nullptr;
    std::string configPath;
    int32_t threadNum = 4;
    int32_t maxNewTokens = 128;
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

napi_value LoadModel(napi_env env, napi_callback_info info) {
    size_t argc = 3;
    napi_value args[3] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    if (argc < 1 || args[0] == nullptr) {
        napi_throw_error(env, nullptr, "loadModel requires a config.json path");
        return nullptr;
    }

    std::string configPath = ReadString(env, args[0]);
    int32_t threadNum = std::clamp(ReadOptionalInt(env, args, argc, 1, 4), 1, 8);
    int32_t maxNewTokens = std::clamp(ReadOptionalInt(env, args, argc, 2, 128), 1, 2048);

    std::string error;
    if (!g_runner.load(configPath, threadNum, maxNewTokens, error)) {
        napi_throw_error(env, nullptr, error.c_str());
        return nullptr;
    }

    return MakeString(env, "loaded: " + configPath);
}

napi_value LoadModelAsync(napi_env env, napi_callback_info info) {
    size_t argc = 3;
    napi_value args[3] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    if (argc < 1 || args[0] == nullptr) {
        napi_throw_error(env, nullptr, "loadModelAsync requires a config.json path");
        return nullptr;
    }

    auto* work = new AsyncLoadWork();
    work->env = env;
    work->configPath = ReadString(env, args[0]);
    work->threadNum = std::clamp(ReadOptionalInt(env, args, argc, 1, 4), 1, 8);
    work->maxNewTokens = std::clamp(ReadOptionalInt(env, args, argc, 2, 128), 1, 2048);

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
            if (!g_runner.load(work->configPath, work->threadNum, work->maxNewTokens, work->error)) {
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
    size_t argc = 2;
    napi_value args[2] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    if (argc < 1 || args[0] == nullptr) {
        napi_throw_error(env, nullptr, "generate requires a prompt");
        return nullptr;
    }

    std::string prompt = ReadString(env, args[0]);
    int32_t maxNewTokens = std::clamp(ReadOptionalInt(env, args, argc, 1, 128), 1, 2048);

    std::string error;
    std::string output = g_runner.generate(prompt, maxNewTokens, error);
    if (!error.empty()) {
        napi_throw_error(env, nullptr, error.c_str());
        return nullptr;
    }

    return MakeString(env, output);
}

napi_value GenerateAsync(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    if (argc < 1 || args[0] == nullptr) {
        napi_throw_error(env, nullptr, "generateAsync requires a prompt");
        return nullptr;
    }

    auto* work = new AsyncGenerateWork();
    work->env = env;
    work->prompt = ReadString(env, args[0]);
    work->maxNewTokens = std::clamp(ReadOptionalInt(env, args, argc, 1, 64), 1, 2048);

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
            work->output = g_runner.generate(work->prompt, work->maxNewTokens, work->error);
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
    size_t argc = 3;
    napi_value args[3] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    if (argc < 1 || args[0] == nullptr) {
        napi_throw_error(env, nullptr, "generateStream requires a prompt");
        return nullptr;
    }
    if (argc < 3 || args[2] == nullptr) {
        napi_throw_error(env, nullptr, "generateStream requires an onChunk callback");
        return nullptr;
    }

    napi_valuetype callbackType = napi_undefined;
    napi_typeof(env, args[2], &callbackType);
    if (callbackType != napi_function) {
        napi_throw_error(env, nullptr, "generateStream onChunk must be a function");
        return nullptr;
    }

    auto* streamWork = new StreamWork();
    streamWork->env = env;
    streamWork->prompt = ReadString(env, args[0]);
    streamWork->maxNewTokens = std::clamp(ReadOptionalInt(env, args, argc, 1, 64), 1, 2048);

    napi_value promise = nullptr;
    napi_create_promise(env, &streamWork->deferred, &promise);

    napi_value resourceName = nullptr;
    napi_create_string_utf8(env, "gemmaGenerateStream", NAPI_AUTO_LENGTH, &resourceName);
    napi_create_threadsafe_function(
        env,
        args[2],
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
            work->output = g_runner.generateStreaming(
                work->prompt,
                work->maxNewTokens,
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
                napi_value result = MakeString(env, work->output);
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
    size_t argc = 3;
    napi_value args[3] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    if (argc < 1 || args[0] == nullptr) {
        napi_throw_error(env, nullptr, "generateChatStream requires chat messages");
        return nullptr;
    }
    if (argc < 3 || args[2] == nullptr) {
        napi_throw_error(env, nullptr, "generateChatStream requires an onChunk callback");
        return nullptr;
    }

    napi_valuetype callbackType = napi_undefined;
    napi_typeof(env, args[2], &callbackType);
    if (callbackType != napi_function) {
        napi_throw_error(env, nullptr, "generateChatStream onChunk must be a function");
        return nullptr;
    }

    auto* streamWork = new StreamWork();
    streamWork->env = env;
    streamWork->useChatMessages = true;
    streamWork->maxNewTokens = std::clamp(ReadOptionalInt(env, args, argc, 1, 64), 1, 2048);

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
        args[2],
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
                work->maxNewTokens,
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
                napi_value result = MakeString(env, work->output);
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
        {"generateChatStream", nullptr, GenerateChatStream, nullptr, nullptr, nullptr, napi_default, nullptr},
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
