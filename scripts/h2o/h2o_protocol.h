#pragma once

#include <cstdint>
#include <string>
#include <vector>

namespace H2o {

enum class QuestionType { Choice, Noul, Score };

struct Option {
    std::string name;
    std::string description;
};

struct Question {
    QuestionType type = QuestionType::Choice;
    std::string state;
    std::string instruction;
    // Choice uses unique names. Noul uses true/false in that order, score uses 0..N-1.
    // Empty noul options select the official default descriptions.
    std::vector<Option> options;
};

struct PreparedQuestion {
    QuestionType type;
    std::string prompt;
    std::vector<Option> options;
    double temperature;
};

struct DecisionResult {
    std::vector<Option> options;
    std::vector<float> logits;
    std::vector<double> probabilities;
    size_t selectedIndex = 0;
    // Official score is the expected ordinal level, not the most likely level.
    double score = 0;
    double confidence = 0;
    int inputTokens = 0;
    int cpuThreads = 0;
    double preprocessingMs = 0;
    double forwardMs = 0;
};

PreparedQuestion prepareQuestion(const Question& question, bool hasImage = false);
DecisionResult readDecision(const PreparedQuestion& question, const std::vector<float>& logits);
const std::vector<std::string>& labels();

} // namespace H2o
