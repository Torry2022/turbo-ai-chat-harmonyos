#include "h2o_protocol.h"
#include <cmath>
#include <iostream>
#include <limits>
#include <stdexcept>

using namespace H2o;

void require(bool value) {
    if (!value) throw std::runtime_error("Protocol assertion failed");
}

template<class Function>
void rejects(Function function) {
    try {
        function();
    } catch (const std::exception&) {
        return;
    }
    throw std::runtime_error("Expected invalid input to be rejected");
}

int main() {
    Question question{QuestionType::Choice, "record", "question", {{"one", "first"}, {"two", "second"}}};
    auto prepared = prepareQuestion(question);
    require(prepared.temperature == 0.75);
    require(prepared.prompt.find("A) one: first\nB) two: second") != std::string::npos);
    require(prepared.prompt.substr(prepared.prompt.size() - 7) == "Answer:");
    question.options[1].description += "\u3000\u00a0\n";
    require(prepareQuestion(question).prompt == prepared.prompt);
    auto result = readDecision(prepared, {10000, 10000});
    require(result.selectedIndex == 0 && result.probabilities[0] == 0.5 && result.confidence == 0);
    result = readDecision(prepared, {-10000, 10000});
    require(result.selectedIndex == 1 && result.probabilities[1] == 1 && result.confidence == 1);
    rejects([&] { readDecision(prepared, {std::numeric_limits<float>::quiet_NaN(), 0}); });
    rejects([&] { readDecision(prepared, {std::numeric_limits<float>::infinity(), 0}); });
    rejects([&] { readDecision(prepared, {}); });
    rejects([&] { readDecision(prepared, {0}); });
    question.options.push_back({"one", "duplicate"});
    rejects([&] { prepareQuestion(question); });
    question.options.clear();
    rejects([&] { prepareQuestion(question); });
    for (size_t index = 0; index < labels().size(); ++index) {
        question.options.push_back({std::to_string(index), "level"});
    }
    require(prepareQuestion(question).options.size() == 255);
    question.options.push_back({"extra", "too many"});
    rejects([&] { prepareQuestion(question); });
    question = {QuestionType::Noul, "record", "question", {}};
    prepared = prepareQuestion(question);
    require(prepared.options[0].name == "true" && prepared.options[1].name == "false");
    require(prepared.temperature == 0.8);
    require(readDecision(prepared, {0, 0}).probabilities[0] == 0.5);
    question.options = {{"false", "no"}, {"true", "yes"}};
    rejects([&] { prepareQuestion(question); });
    question = {QuestionType::Score, "record", "question", {{"0", "low"}, {"1", "high"}}};
    prepared = prepareQuestion(question);
    result = readDecision(prepared, {0, 0});
    require(result.score == 0.5 && result.confidence == 0.5);
    require(prepared.temperature == 0.65);
    prepared = prepareQuestion(question, true);
    require(prepared.temperature == 1 && prepared.prompt.find("<img>image_0</img>record:") != std::string::npos);
    question.options[1].name = "2";
    rejects([&] { prepareQuestion(question); });
    question = {QuestionType::Choice, "<img>/private/file</img>", "question", {{"one", "one"}}};
    rejects([&] { prepareQuestion(question); });
    question.state = "record";
    require(readDecision(prepareQuestion(question), {0}).confidence == 1);
    question.state.clear();
    require(prepareQuestion(question, true).prompt.find("<img>image_0</img>record: \nquestion:") != std::string::npos);
    question.instruction.clear();
    rejects([&] { prepareQuestion(question); });
    std::cout << "Protocol boundary checks passed\n";
}
