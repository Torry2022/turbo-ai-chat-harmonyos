#include "h2o_protocol.h"
#include "h2o_contract.h"

#include <algorithm>
#include <cmath>
#include <set>
#include <stdexcept>

namespace H2o {
namespace {

void validateText(const std::string& text) {
    // Omni interprets these as media inputs, including local file paths.
    for (const char* marker : {"<img>", "<audio>", "<video>"}) {
        if (text.find(marker) != std::string::npos) {
            throw std::invalid_argument("Use the image argument for media inputs");
        }
    }
}

} // namespace

const std::vector<std::string>& labels() { return Contract::labels; }

PreparedQuestion prepareQuestion(const Question& question, bool hasImage) {
    if (question.instruction.empty()) {
        throw std::invalid_argument("Instruction must not be empty");
    }
    PreparedQuestion prepared{question.type, "", question.options, 0};
    switch (question.type) {
        case QuestionType::Choice: prepared.temperature = 0.75; break;
        case QuestionType::Noul:
            prepared.temperature = 0.8;
            if (prepared.options.empty()) {
                prepared.options = {{"true", "the statement holds"}, {"false", "it does not"}};
            }
            if (prepared.options.size() != 2 || prepared.options[0].name != "true" ||
                prepared.options[1].name != "false") {
                throw std::invalid_argument("Noul options must be true and false in that order");
            }
            if (prepared.options[0].description.empty()) prepared.options[0].description = "the statement holds";
            if (prepared.options[1].description.empty()) prepared.options[1].description = "it does not";
            break;
        case QuestionType::Score: prepared.temperature = 0.65; break;
        default: throw std::invalid_argument("Unknown question type");
    }
    if (prepared.options.empty() || prepared.options.size() > labels().size()) {
        throw std::invalid_argument("A decision requires 1 to 255 options");
    }
    validateText(question.state);
    validateText(question.instruction);
    std::set<std::string> names;
    std::string user = (hasImage ? "<img>image_0</img>" : "") +
        std::string("record: ") + question.state + "\nquestion: " + question.instruction + "\noptions:\n";
    for (size_t index = 0; index < prepared.options.size(); ++index) {
        const auto& option = prepared.options[index];
        if (option.name.empty() || !names.insert(option.name).second) {
            throw std::invalid_argument("Option names must be nonempty and unique");
        }
        if (question.type == QuestionType::Score && option.name != std::to_string(index)) {
            throw std::invalid_argument("Score option names must be consecutive levels starting at zero");
        }
        validateText(option.name);
        validateText(option.description);
        if (index) user += '\n';
        user += labels()[index] + ") " + option.name + ": " + option.description;
    }
    // Match Python's Unicode strip at the end of the final option description.
    const std::string whitespace = " \t\r\n\f\v\x1c\x1d\x1e\x1f"
        "\u0085\u00a0\u1680\u2000\u2001\u2002\u2003\u2004\u2005\u2006"
        "\u2007\u2008\u2009\u200a\u2028\u2029\u202f\u205f\u3000";
    while (!user.empty()) {
        size_t start = user.size() - 1;
        while (start > 0 && (static_cast<unsigned char>(user[start]) & 0xc0) == 0x80) --start;
        if (whitespace.find(user.substr(start)) == std::string::npos) break;
        user.resize(start);
    }
    prepared.prompt = std::string("<|im_start|>system\n") + Contract::system +
        "<|im_end|>\n<|im_start|>user\n" + user +
        "<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\nAnswer:";
    if (hasImage) prepared.temperature = 1.0;
    return prepared;
}

DecisionResult readDecision(const PreparedQuestion& question, const std::vector<float>& logits) {
    if (logits.empty() || logits.size() != question.options.size() ||
        !std::isfinite(question.temperature) || question.temperature <= 0) {
        throw std::invalid_argument("Invalid candidate logits or temperature");
    }
    for (float value : logits) {
        if (!std::isfinite(value)) throw std::runtime_error("Non-finite candidate logit");
    }
    DecisionResult result;
    result.options = question.options;
    result.logits = logits;
    const auto maximum = std::max_element(logits.begin(), logits.end());
    result.selectedIndex = static_cast<size_t>(maximum - logits.begin());
    double sum = 0;
    for (float value : logits) {
        const double probability = std::exp((static_cast<double>(value) - *maximum) / question.temperature);
        result.probabilities.push_back(probability);
        sum += probability;
    }
    for (size_t index = 0; index < logits.size(); ++index) {
        result.probabilities[index] /= sum;
        result.score += index * result.probabilities[index];
    }
    const double top = result.probabilities[result.selectedIndex];
    const double uniform = 1.0 / logits.size();
    result.confidence = question.type == QuestionType::Choice && logits.size() > 1 ?
        (top - uniform) / (1 - uniform) : top;
    return result;
}

} // namespace H2o
