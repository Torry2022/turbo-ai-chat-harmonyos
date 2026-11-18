#include "embedding_napi.h"
#include "embedding_runner.h"
#include <stdexcept>

namespace {
napi_value stringValue(napi_env env, const std::string& text) {
    napi_value value = nullptr;
    napi_create_string_utf8(env, text.c_str(), text.size(), &value);
    return value;
}

std::string readString(napi_env env, napi_value value) {
    napi_valuetype type;
    napi_typeof(env, value, &type);
    if (type != napi_string) throw std::runtime_error("向量输入必须是文本");
    size_t size = 0;
    napi_get_value_string_utf8(env, value, nullptr, 0, &size);
    std::string text(size + 1, '\0');
    napi_get_value_string_utf8(env, value, text.data(), text.size(), &size);
    text.resize(size);
    return text;
}

struct EmbeddingWork {
    napi_async_work work = nullptr;
    napi_deferred deferred = nullptr;
    std::string operation, config, error;
    int threads = 4, dimension = 0, actualThreads = 0;
    std::vector<std::string> texts;
    EmbeddingResult result;
};

napi_value embeddingAsync(napi_env env, napi_callback_info info) {
    size_t argc = 4;
    napi_value args[4] = {};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    auto task = std::make_unique<EmbeddingWork>();
    try {
        if (argc != 4) throw std::runtime_error("向量调用参数不完整");
        task->operation = readString(env, args[0]);
        task->config = readString(env, args[1]);
        if (napi_get_value_int32(env, args[2], &task->threads) != napi_ok) throw std::runtime_error("向量模型线程配置无效");
        bool array = false;
        napi_is_array(env, args[3], &array);
        if (!array) throw std::runtime_error("向量输入必须是文本数组");
        uint32_t count = 0;
        napi_get_array_length(env, args[3], &count);
        if (count > 64) throw std::runtime_error("单次最多处理 64 条文本");
        for (uint32_t i = 0; i < count; ++i) {
            napi_value item = nullptr;
            napi_get_element(env, args[3], i, &item);
            task->texts.push_back(readString(env, item));
        }
    } catch (const std::exception& error) {
        napi_throw_type_error(env, nullptr, error.what());
        return nullptr;
    }
    napi_value promise = nullptr;
    napi_create_promise(env, &task->deferred, &promise);
    napi_status queued = napi_create_async_work(env, nullptr, stringValue(env, "embeddingAsync"),
        [](napi_env, void* data) {
            auto* work = static_cast<EmbeddingWork*>(data);
            try {
                if (work->operation == "load") loadEmbedding(work->config, work->threads);
                else if (work->operation == "encode") work->result = encodeEmbedding(work->texts);
                else if (work->operation == "release") releaseEmbedding();
                else throw std::runtime_error("未知向量操作");
                work->dimension = embeddingDimension();
                work->actualThreads = embeddingThreads();
            } catch (const std::exception& error) { work->error = error.what(); }
        },
        [](napi_env env, napi_status status, void* data) {
            std::unique_ptr<EmbeddingWork> work(static_cast<EmbeddingWork*>(data));
            if (status != napi_ok && work->error.empty()) work->error = "向量任务未完成";
            if (!work->error.empty()) {
                napi_value error = nullptr;
                napi_create_error(env, nullptr, stringValue(env, work->error), &error);
                napi_reject_deferred(env, work->deferred, error);
            } else {
                napi_value result, vectors, value;
                napi_create_object(env, &result);
                napi_create_array_with_length(env, work->result.vectors.size(), &vectors);
                for (size_t i = 0; i < work->result.vectors.size(); ++i) {
                    napi_value row;
                    const auto& values = work->result.vectors[i];
                    napi_create_array_with_length(env, values.size(), &row);
                    for (size_t j = 0; j < values.size(); ++j) {
                        napi_create_double(env, values[j], &value);
                        napi_set_element(env, row, j, value);
                    }
                    napi_set_element(env, vectors, i, row);
                }
                napi_set_named_property(env, result, "vectors", vectors);
                napi_create_int64(env, work->result.inputTokens, &value);
                napi_set_named_property(env, result, "inputTokens", value);
                napi_create_int32(env, work->dimension, &value);
                napi_set_named_property(env, result, "dimension", value);
                napi_create_int32(env, work->actualThreads, &value);
                napi_set_named_property(env, result, "threads", value);
                napi_resolve_deferred(env, work->deferred, result);
            }
            napi_delete_async_work(env, work->work);
        }, task.get(), &task->work);
    if (queued == napi_ok) queued = napi_queue_async_work(env, task->work);
    if (queued != napi_ok) {
        napi_value error;
        napi_create_error(env, nullptr, stringValue(env, "无法启动向量任务"), &error);
        napi_reject_deferred(env, task->deferred, error);
        if (task->work) napi_delete_async_work(env, task->work);
    } else task.release();
    return promise;
}
}

void RegisterEmbeddingApi(napi_env env, napi_value exports) {
    napi_property_descriptor descriptor = {"embeddingAsync", nullptr, embeddingAsync, nullptr, nullptr, nullptr, napi_default, nullptr};
    napi_define_properties(env, exports, 1, &descriptor);
}
