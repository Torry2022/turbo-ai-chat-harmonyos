#include "laya_tokenizer.h"

#include <cstdint>
#include <fstream>
#include <stdexcept>

namespace {

uint32_t readU32(std::ifstream& stream) {
    uint32_t value = 0;
    stream.read(reinterpret_cast<char*>(&value), sizeof(value));
    if (!stream) throw std::runtime_error("Incomplete Laya tokenizer file");
    return value;
}

std::string readText(std::ifstream& stream) {
    std::string result(readU32(stream), '\0');
    stream.read(&result[0], result.size());
    if (!stream) throw std::runtime_error("Incomplete Laya tokenizer file");
    return result;
}

std::vector<std::string> unicodeCharacters(const std::string& text) {
    std::vector<std::string> characters;
    for (size_t index = 0; index < text.size();) {
        const unsigned char first = static_cast<unsigned char>(text[index]);
        const size_t width = first < 0x80 ? 1 : first < 0xe0 ? 2 : first < 0xf0 ? 3 : 4;
        if (index + width > text.size()) throw std::runtime_error("Invalid UTF-8 input");
        characters.emplace_back(text.substr(index, width));
        index += width;
    }
    return characters;
}

} // namespace

size_t LayaTokenizer::PairHash::operator()(const std::pair<std::string, std::string>& pair) const {
    const size_t left = std::hash<std::string>{}(pair.first);
    const size_t right = std::hash<std::string>{}(pair.second);
    return left ^ (right + 0x9e3779b9 + (left << 6) + (left >> 2));
}

LayaTokenizer::LayaTokenizer(const std::string& path) {
    std::ifstream stream(path, std::ios::binary);
    char magic[5] = {};
    stream.read(magic, sizeof(magic));
    if (!stream || std::string(magic, sizeof(magic)) != "LYTK1") {
        throw std::runtime_error("Invalid Laya tokenizer file");
    }
    const uint32_t vocabSize = readU32(stream);
    const uint32_t mergeSize = readU32(stream);
    vocabulary_.reserve(vocabSize);
    merges_.reserve(mergeSize);
    for (uint32_t index = 0; index < vocabSize; ++index) {
        std::string token = readText(stream);
        vocabulary_.emplace(std::move(token), static_cast<int>(readU32(stream)));
    }
    for (uint32_t index = 0; index < mergeSize; ++index) {
        std::string left = readText(stream);
        std::string right = readText(stream);
        merges_.emplace(std::make_pair(std::move(left), std::move(right)), static_cast<int>(index));
    }
}

std::vector<int> LayaTokenizer::encode(const std::string& text) const {
    if (text.empty()) return {};
    const std::string marker = "\xe2\x96\x81";
    std::string normalized = text[0] == ' ' ? "" : marker;
    for (char value : text) {
        if (value == ' ') normalized += marker;
        else normalized += value;
    }
    std::vector<int> result;
    for (size_t start = 0; start < normalized.size();) {
        size_t end = normalized.find(marker, start + marker.size());
        if (end == std::string::npos) end = normalized.size();
        std::vector<std::string> symbols = unicodeCharacters(normalized.substr(start, end - start));
        while (symbols.size() > 1) {
            int bestRank = INT32_MAX;
            size_t best = symbols.size();
            for (size_t i = 0; i + 1 < symbols.size(); ++i) {
                const auto found = merges_.find({symbols[i], symbols[i + 1]});
                if (found != merges_.end() && found->second < bestRank) {
                    bestRank = found->second;
                    best = i;
                }
            }
            if (best == symbols.size()) break;
            symbols[best] += symbols[best + 1];
            symbols.erase(symbols.begin() + best + 1);
        }
        for (const std::string& symbol : symbols) {
            const auto token = vocabulary_.find(symbol);
            if (token != vocabulary_.end()) {
                result.push_back(token->second);
                continue;
            }
            for (unsigned char byte : symbol) {
                const char hex[] = "0123456789ABCDEF";
                std::string fallback = "<0x00>";
                fallback[3] = hex[byte >> 4];
                fallback[4] = hex[byte & 15];
                const auto fallbackToken = vocabulary_.find(fallback);
                if (fallbackToken == vocabulary_.end()) throw std::runtime_error("Missing byte fallback token");
                result.push_back(fallbackToken->second);
            }
        }
        start = end;
    }
    return result;
}

#ifdef LAYA_TOKENIZER_CLI
#include <iostream>
int main(int argc, char** argv) {
    if (argc != 2 && argc != 3) return 2;
    LayaTokenizer tokenizer(argv[1]);
    auto printIds = [&](const std::string& text) {
        for (int id : tokenizer.encode(text)) std::cout << id << ' ';
        std::cout << '\n';
    };
    if (argc == 3) printIds(argv[2]);
    else {
        std::string line;
        while (std::getline(std::cin, line)) printIds(line);
    }
}
#endif
