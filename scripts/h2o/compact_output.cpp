#include "MNN_generated.h"
#include <fstream>
#include <iostream>
#include <iterator>
#include <memory>
#include <vector>

// Called by compact_model.py after checking the source model and selecting label rows.
int main(int argc, char** argv) {
    if (argc != 4) return 2;
    std::ifstream graph(argv[1], std::ios::binary);
    std::ifstream weights(argv[2], std::ios::binary);
    if (!graph || !weights) return 3;
    std::vector<char> bytes((std::istreambuf_iterator<char>(graph)), {});
    flatbuffers::Verifier verifier(reinterpret_cast<const uint8_t*>(bytes.data()), bytes.size());
    if (!MNN::VerifyNetBuffer(verifier)) return 4;
    std::unique_ptr<MNN::NetT> net(MNN::GetNet(bytes.data())->UnPack());
    int changed = 0;
    int reshaped = 0;
    for (auto& op : net->oplists) {
        if (op->name == "/lm/lm_head/Linear/post_reshape") {
            auto* reshape = op->main.AsReshape();
            if (!reshape || reshape->dims != std::vector<int32_t>({1, -1, 248320})) return 9;
            reshape->dims.back() = 255;
            ++reshaped;
        }
        if (op->name != "/lm/lm_head/Linear") continue;
        auto* conv = op->main.AsConvolution2D();
        if (!conv || !conv->common || conv->common->inputCount != 2560 ||
            conv->common->outputCount != 248320 || !conv->quanParameter ||
            conv->quanParameter->type != 3 || conv->external.size() != 5 ||
            conv->external[0] != 3793581568 || conv->external[1] != 1271398400 ||
            conv->external[2] != 0 || conv->external[3] != 0 || conv->external[4] != 0) return 5;
        auto& buffer = conv->quanParameter->buffer;
        buffer.resize(255 * 2560 * sizeof(uint16_t));
        weights.read(reinterpret_cast<char*>(buffer.data()), buffer.size());
        if (!weights || weights.peek() != std::char_traits<char>::eof()) return 6;
        conv->common->outputCount = 255;
        // External loading supplies zero bias for the original bias-free head.
        conv->bias.assign(255, 0.0f);
        conv->quanParameter->weightSize = 255 * 2560;
        conv->external.clear();
        ++changed;
    }
    if (changed != 1 || reshaped != 1) return 7;
    flatbuffers::FlatBufferBuilder builder;
    builder.Finish(MNN::Net::Pack(builder, net.get()));
    std::ofstream output(argv[3], std::ios::binary);
    output.write(reinterpret_cast<const char*>(builder.GetBufferPointer()), builder.GetSize());
    return output ? 0 : 8;
}
