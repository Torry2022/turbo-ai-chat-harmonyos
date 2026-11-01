#pragma once

#include <MNN/expr/Executor.hpp>
#include <array>
#include <mutex>
#include <regex>
#include <stdexcept>
#include <string>

// The native reranker accepts up to 16 threads. Prepare that capacity before
// creating any model backend; each runtime still requests its own width.
inline void PrepareMnnCpuCapacity(const std::string& modelConfig = "") {
    static std::array<std::once_flag, 3> initialized;
    MNN::BackendConfig backend;
    std::smatch power;
    static const std::regex pattern("\"power\"\\s*:\\s*\"(high|low|normal)\"");
    // Only the top-level power config controls the text CPU runtime. Nested
    // multimodal/template objects may contain unrelated keys with the same name.
    int depth = 0;
    bool quoted = false, escaped = false;
    for (size_t i = 0; i < modelConfig.size(); ++i) {
        const char c = modelConfig[i];
        if (quoted) {
            if (escaped) escaped = false;
            else if (c == '\\') escaped = true;
            else if (c == '"') quoted = false;
            continue;
        }
        if (c == '"') {
            if (depth == 1 && modelConfig.compare(i, 7, "\"power\"") == 0) {
                const auto field = modelConfig.substr(i);
                if (std::regex_search(field, power, pattern, std::regex_constants::match_continuous)) {
                    if (power[1] == "high") backend.power = MNN::BackendConfig::Power_High;
                    if (power[1] == "low") backend.power = MNN::BackendConfig::Power_Low;
                }
                break;
            }
            quoted = true;
        } else if (c == '{' || c == '[') ++depth;
        else if (c == '}' || c == ']') --depth;
    }
    std::call_once(initialized[static_cast<size_t>(backend.power)], [&] {
        auto capacity = MNN::Express::Executor::newExecutor(MNN_FORWARD_CPU, backend, 16);
        if (!capacity) throw std::runtime_error("Cannot initialize MNN CPU capacity");
        // MNN retains its worker pool after this temporary executor is released.
    });
}
