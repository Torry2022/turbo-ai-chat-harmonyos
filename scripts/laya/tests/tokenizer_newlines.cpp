// Expected IDs from the published multilingual tokenizer.json (SHA-256 609d8f4c...ab5b6f).
// Compile with laya_tokenizer.cpp and pass the matching laya.tokbin as argv[1].
#include "../laya_tokenizer.h"
#include <iostream>
#include <vector>
struct Case { const char* text; std::vector<int> expected; };
int main(int argc, char** argv) {
    if (argc != 2) return 2;
    LayaTokenizer tokenizer(argv[1]);
    const std::vector<Case> cases = {
        {"", {}},
        {"加载模型后应用立即崩溃。", {154258, 43936, 235725, 25601, 63110, 173779, 235362}},
        {"alpha beta", {12603, 18820}},
        {"甲\n乙", {102729, 108, 235248, 238881}},
        {"\n乙", {108, 235248, 238881}},
        {"甲\n", {102729, 108}},
        {"\n", {108}},
        {"\n\n", {109}},
        {"甲\n\n乙", {102729, 109, 235248, 238881}},
        {"甲\r\n乙", {102729, 235316, 108, 235248, 238881}},
        {"\r\n", {2722, 108}},
        {"甲\r乙", {102729, 235316, 238881}},
        {"甲 \n 乙", {102729, 235248, 108, 235248, 238881}},
        {" \n ", {235248, 108, 235248}},
        {"甲\n乙\n丙", {102729, 108, 235248, 238881, 108, 235248, 240706}},
        {"alpha\nbeta", {12603, 108, 18820}},
        {"🙂\n🙂", {33359, 108, 33359}},
        {"首行\n\n  后一行\r\n结束", {74518, 235599, 109, 235248, 67330, 116741, 235316, 108, 235248, 35288}},
        {"甲\n\n\n乙", {102729, 110, 235248, 238881}},
        {"甲\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n乙", {102729, 137, 235248, 238881}},
        {"甲\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n乙", {102729, 138, 235248, 238881}},
        {"甲\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n乙", {102729, 138, 108, 235248, 238881}},
        {"甲\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n乙", {102729, 138, 109, 235248, 238881}},
        {"甲\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n乙", {102729, 138, 138, 235248, 238881}},
        {"甲\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n乙", {102729, 138, 138, 108, 235248, 238881}},
        {"甲\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n乙", {102729, 138, 138, 109, 235248, 238881}},
        {"甲\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n乙", {102729, 138, 138, 110, 235248, 238881}},
        {"\t", {235248, 226}},
        {"\t\t", {255969}},
        {"\t\talpha", {255969, 12603}},
        {"甲\n\t\t乙", {102729, 108, 255969, 235248, 238881}},
        {"\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\n乙", {255998, 108, 235248, 238881}},
        {"\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t乙", {255998, 235248, 226, 238881}},
    };
    for (size_t i = 0; i < cases.size(); ++i) {
        if (tokenizer.encode(cases[i].text) != cases[i].expected) {
            std::cerr << "Tokenizer regression failed at case " << i << "\n";
            return 1;
        }
    }
    std::cout << "PASS " << cases.size() << " newline and unchanged-text cases\n";
}
