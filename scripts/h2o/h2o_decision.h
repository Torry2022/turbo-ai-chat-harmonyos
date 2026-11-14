#pragma once

#include "h2o_protocol.h"
#include <memory>
#include <mutex>

namespace H2o {

struct Image {
    int width = 0;
    int height = 0;
    // Packed RGB, three bytes per pixel, no row padding.
    std::vector<uint8_t> rgb;
};

class DecisionModel {
public:
    DecisionModel();
    ~DecisionModel();
    DecisionModel(const DecisionModel&) = delete;
    DecisionModel& operator=(const DecisionModel&) = delete;

    void load(const std::string& configPath, int threads = 4, int maxInputTokens = 40960);
    DecisionResult decide(const Question& question, const Image* image = nullptr);
    void release();
    bool isLoaded() const;
    int cpuThreadCount() const;

private:
    struct Runtime;
    mutable std::mutex mutex_;
    std::unique_ptr<Runtime> runtime_;
};

} // namespace H2o
