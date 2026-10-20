#pragma once

#include <string>
#include <unordered_map>
#include <vector>

class LayaTokenizer {
public:
    explicit LayaTokenizer(const std::string& path);
    std::vector<int> encode(const std::string& text) const;

private:
    struct PairHash {
        size_t operator()(const std::pair<std::string, std::string>& pair) const;
    };
    std::unordered_map<std::string, int> vocabulary_;
    std::unordered_map<std::pair<std::string, std::string>, int, PairHash> merges_;
    std::vector<std::pair<std::string, int>> whitespaceTokens_;
    std::vector<int> encodeText(const std::string& text) const;
};
