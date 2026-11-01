// Link against the pinned MNN build, with its original ThreadPool.cpp.
// Runtime inspection uses internal headers only in this host regression.
#include <MNN/expr/Executor.hpp>
#include <MNN/expr/ExecutorScope.hpp>
#include <MNN/expr/MathOp.hpp>
#include <MNN/expr/NeuralNetWorkOp.hpp>
#include "core/Backend.hpp"
#include "../entry/src/main/cpp/mnn_cpu_capacity.h"
#include <cmath>
#include <fstream>
#include <future>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

using namespace MNN;
using namespace MNN::Express;

void check(bool ok) { if (!ok) throw std::runtime_error("Executor thread regression"); }
void snapshot(const char* label) {
    std::ifstream status("/proc/self/status");
    std::string line;
    std::cout << label << '\n';
    while (std::getline(status, line)) {
        if (line.rfind("VmRSS:", 0) == 0 || line.rfind("Threads:", 0) == 0)
            std::cout << line << '\n';
    }
}
void execute(const std::shared_ptr<Executor>& executor, int width) {
    ExecutorScope scope(executor);
    Backend::Info info;
    check(Executor::getRuntime().first.at(MNN_FORWARD_CPU)->onCheckInfo(info));
    check(info.numThread == width);
    std::vector<float> data(64 * 64, 1.f);
    auto a = _Const(data.data(), {64, 64});
    auto b = _Const(data.data(), {64, 64});
    auto result = _MatMul(a, b);
    auto output = result->readMap<float>();
    check(output != nullptr);
    for (int i = 0; i < 64 * 64; ++i) check(std::abs(output[i] - 64.f) < .001f);
}
int main(int argc, char**) {
    BackendConfig config;
    config.precision = BackendConfig::Precision_Low;
    config.memory = BackendConfig::Memory_Low;
    snapshot("before initialization");
    if (argc > 1) {
        PrepareMnnCpuCapacity();
        PrepareMnnCpuCapacity();
    }
    snapshot("after capacity initialization");
    std::vector<std::shared_ptr<Executor>> retained;
    std::vector<int> widths{4, 6, 8, 2, 4, 16, 2, 8, 6, 4};
    for (int width : widths) {
        auto executor = Executor::newExecutor(MNN_FORWARD_CPU, config, width);
        execute(executor, width);
        retained.push_back(executor);
    }
    auto first = std::async(std::launch::async, [&] { execute(retained[0], widths[0]); });
    execute(retained[1], widths[1]);
    first.get();
    retained.erase(retained.begin() + 1);
    execute(retained[0], widths[0]);
    auto reloaded = Executor::newExecutor(MNN_FORWARD_CPU, config, 6);
    execute(reloaded, 6);
    for (const auto& mode : {std::string("high"), std::string("low")}) {
        PrepareMnnCpuCapacity("{\"mllm\":{\"power\":\"normal\"},\"power\":\"" + mode + "\"}");
        config.power = mode == "high" ? BackendConfig::Power_High : BackendConfig::Power_Low;
        for (int width : {4, 8, 2, 6}) execute(Executor::newExecutor(MNN_FORWARD_CPU, config, width), width);
    }
    snapshot("after independent runtimes and reload");
    std::cout << "PASS public Executor capacity, retained widths, operators and reload\n";
}
