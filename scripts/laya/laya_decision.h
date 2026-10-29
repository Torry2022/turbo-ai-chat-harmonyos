#pragma once

#include <string>
#include <vector>

void loadLayaDecision(const std::string& modelPath, const std::string& tokenizerPath);

std::string runLayaDecision(const std::string& modelPath, const std::string& tokenizerPath,
    const std::string& state, const std::string& type, const std::string& instruction,
    const std::vector<std::string>& options);

void releaseLayaDecision();
