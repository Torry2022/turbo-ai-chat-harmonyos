#pragma once

#include <functional>
#include <ostream>
#include <streambuf>
#include <string>

namespace {

std::string AssistantOutputPrefix(const std::string& prompt) {
    const auto end = prompt.find_last_not_of(" \t\r\n");
    const std::string tag = "<think>";
    if (end != std::string::npos && end + 1 >= tag.size()
        && prompt.compare(end + 1 - tag.size(), tag.size(), tag) == 0) {
        return tag + "\n";
    }
    return {};
}

bool IsUtf8Continuation(unsigned char value) {
    return (value & 0xC0) == 0x80;
}

bool IsValidUtf8Sequence(const std::string& text, size_t index, size_t length) {
    if (index + length > text.size()) {
        return false;
    }

    const auto first = static_cast<unsigned char>(text[index]);
    if (length == 1) {
        return first <= 0x7F;
    }
    if (length == 2) {
        return IsUtf8Continuation(static_cast<unsigned char>(text[index + 1]));
    }
    if (length == 3) {
        const auto second = static_cast<unsigned char>(text[index + 1]);
        const auto third = static_cast<unsigned char>(text[index + 2]);
        if (!IsUtf8Continuation(second) || !IsUtf8Continuation(third)) {
            return false;
        }
        return (first != 0xE0 || second >= 0xA0) && (first != 0xED || second <= 0x9F);
    }
    if (length == 4) {
        const auto second = static_cast<unsigned char>(text[index + 1]);
        const auto third = static_cast<unsigned char>(text[index + 2]);
        const auto fourth = static_cast<unsigned char>(text[index + 3]);
        if (!IsUtf8Continuation(second) || !IsUtf8Continuation(third) || !IsUtf8Continuation(fourth)) {
            return false;
        }
        return (first != 0xF0 || second >= 0x90) && (first != 0xF4 || second <= 0x8F);
    }
    return false;
}

size_t Utf8SequenceLength(unsigned char value) {
    if (value <= 0x7F) {
        return 1;
    }
    if (value >= 0xC2 && value <= 0xDF) {
        return 2;
    }
    if (value >= 0xE0 && value <= 0xEF) {
        return 3;
    }
    if (value >= 0xF0 && value <= 0xF4) {
        return 4;
    }
    return 0;
}

size_t ValidUtf8PrefixLength(const std::string& text) {
    size_t index = 0;
    while (index < text.size()) {
        const size_t length = Utf8SequenceLength(static_cast<unsigned char>(text[index]));
        if (length == 0) {
            break;
        }
        if (index + length > text.size()) {
            break;
        }
        if (!IsValidUtf8Sequence(text, index, length)) {
            break;
        }
        index += length;
    }
    return index;
}

bool StartsWithInvalidUtf8Sequence(const std::string& text) {
    if (text.empty()) {
        return false;
    }
    const size_t length = Utf8SequenceLength(static_cast<unsigned char>(text[0]));
    if (length == 0) {
        return true;
    }
    if (text.size() < length) {
        return false;
    }
    return !IsValidUtf8Sequence(text, 0, length);
}

class ChunkStreamBuffer : public std::streambuf {
public:
    explicit ChunkStreamBuffer(
        const std::function<void(const std::string&)>& onChunk,
        const std::function<bool()>& shouldStop = nullptr,
        const std::string& prefix = "")
        : onChunk_(onChunk), shouldStop_(shouldStop), prefix_(prefix) {}

    const std::string& output() const {
        return output_;
    }

    const std::string& rawOutput() const {
        return rawOutput_;
    }

protected:
    std::streamsize xsputn(const char* s, std::streamsize n) override {
        if (n <= 0) {
            return 0;
        }
        if (ShouldStop()) {
            return n;
        }
        std::string chunk(s, static_cast<size_t>(n));
        rawOutput_ += chunk;
        if (!prefix_.empty()) {
            prefixProbe_ += chunk;
            const std::string tag = "<think>";
            if (prefixProbe_.size() < tag.size()
                && tag.compare(0, prefixProbe_.size(), prefixProbe_) == 0) {
                return n;
            }
            chunk = prefixProbe_.compare(0, tag.size(), tag) == 0
                ? prefixProbe_ : prefix_ + prefixProbe_;
            prefix_.clear();
            prefixProbe_.clear();
        }
        output_ += chunk;
        pendingChunk_ += chunk;
        FlushPendingChunk(false);
        ShouldStop();
        return n;
    }

    int overflow(int c) override {
        if (c == EOF) {
            return c;
        }
        if (ShouldStop()) {
            return c;
        }
        char value = static_cast<char>(c);
        xsputn(&value, 1);
        ShouldStop();
        return c;
    }

    int sync() override {
        // sync() may occur between bytes of one UTF-8 character. Keep an
        // incomplete suffix until the following write completes it.
        if (!ShouldStop()) {
            FlushPendingChunk(false);
        }
        return 0;
    }

private:
    bool ShouldStop() const {
        return shouldStop_ && shouldStop_();
    }

    void FlushPendingChunk(bool force) {
        if (!onChunk_) {
            pendingChunk_.clear();
            return;
        }

        while (!pendingChunk_.empty()) {
            const size_t prefixLength = ValidUtf8PrefixLength(pendingChunk_);
            if (prefixLength > 0) {
                onChunk_(pendingChunk_.substr(0, prefixLength));
                pendingChunk_.erase(0, prefixLength);
                continue;
            }
            if (StartsWithInvalidUtf8Sequence(pendingChunk_)) {
                pendingChunk_.erase(0, 1);
                continue;
            }
            break;
        }
        if (force) {
            pendingChunk_.clear();
        }
    }

    std::function<void(const std::string&)> onChunk_;
    std::function<bool()> shouldStop_;
    std::string output_;
    std::string rawOutput_;
    std::string pendingChunk_;
    std::string prefix_;
    std::string prefixProbe_;
};

} // namespace
