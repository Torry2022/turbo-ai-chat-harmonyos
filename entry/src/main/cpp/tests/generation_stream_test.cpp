// Standalone C++17 test; no MNN model or runtime library is needed.
#include "../generation_stream.h"
#include <cassert>

int main() {
    assert(AssistantOutputPrefix("assistant\n<think>\n") == "<think>\n");
    assert(AssistantOutputPrefix("assistant\n<think>\n</think>\n").empty());
    assert(AssistantOutputPrefix("user mentions <think> but asks a question").empty());
    assert(AssistantOutputPrefix("").empty());

    ChunkStreamBuffer emptyBuffer(nullptr, []() { return true; }, "<think>\n");
    std::ostream emptyOutput(&emptyBuffer);
    emptyOutput.exceptions(std::ios::badbit | std::ios::failbit);
    emptyOutput << "discarded" << std::flush;
    assert(emptyOutput.good());
    assert(emptyBuffer.output().empty());
    assert(emptyBuffer.rawOutput().empty());

    std::string streamed;
    bool cancelled = false;
    ChunkStreamBuffer buffer([&](const std::string& s) { streamed += s; },
                             [&]() { return cancelled; }, "<think>\n");
    std::ostream output(&buffer);
    output.exceptions(std::ios::badbit | std::ios::failbit);
    output << "analysis" << "</think>answer" << std::flush;
    assert(streamed == "<think>\nanalysis</think>answer");
    assert(buffer.output() == streamed);
    assert(buffer.rawOutput() == "analysis</think>answer");
    cancelled = true;
    output << "discarded" << std::flush;
    assert(output.good());
    assert(buffer.output() == streamed);

    std::string explicitThinking;
    ChunkStreamBuffer explicitBuffer([&](const std::string& s) { explicitThinking += s; },
                                     nullptr, "<think>\n");
    std::ostream explicitOutput(&explicitBuffer);
    explicitOutput << "<thi" << "nk>analysis</think>answer" << std::flush;
    assert(explicitThinking == "<think>analysis</think>answer");

    std::string plain;
    ChunkStreamBuffer plainBuffer([&](const std::string& s) { plain += s; });
    std::ostream plainOutput(&plainBuffer);
    plainOutput << "ordinary answer" << std::flush;
    assert(plain == "ordinary answer");

    std::string utf8;
    ChunkStreamBuffer utf8Buffer([&](const std::string& s) { utf8 += s; });
    std::ostream utf8Output(&utf8Buffer);
    utf8Output << "\xe4" << std::flush;
    assert(utf8.empty());
    utf8Output << "\xbd\xa0" << std::flush;
    assert(utf8 == "\xe4\xbd\xa0");
}
