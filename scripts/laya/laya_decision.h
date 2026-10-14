#pragma once

#include <string>
#include <vector>

std::string runLayaDecision(const std::string& modelPath, const std::string& tokenizerPath,
    const std::string& state, const std::string& type, const std::string& instruction,
    const std::vector<std::string>& options);

void releaseLayaDecision();
