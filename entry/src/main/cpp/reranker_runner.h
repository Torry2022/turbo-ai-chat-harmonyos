#pragma once
#include <string>
#include <cstdint>
#include <vector>

void loadReranker(const std::string& configPath, int threads, int maxInputTokens);
std::vector<float> scoreReranker(const std::string& query, const std::vector<std::string>& documents, uint64_t epoch);
uint64_t rerankerEpoch();
void cancelReranker();
void releaseReranker();
