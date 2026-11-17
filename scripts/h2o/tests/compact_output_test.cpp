#include "MNN_generated.h"
#include <cassert>
#include <fstream>
#include <iostream>
#include <iterator>
#include <memory>
#include <string>
#include <vector>

void writeGraph(const std::string& path, int outputs = 248320, bool withReshape = true,
                int reshapeOutputs = 248320) {
    MNN::NetT net;
    auto head = std::unique_ptr<MNN::OpT>(new MNN::OpT);
    head->name = "/lm/lm_head/Linear";
    head->type = MNN::OpType_Convolution;
    head->main.Set(MNN::Convolution2DT{});
    auto* conv = head->main.AsConvolution2D();
    conv->common.reset(new MNN::Convolution2DCommonT);
    conv->common->inputCount = 2560;
    conv->common->outputCount = outputs;
    conv->quanParameter.reset(new MNN::IDSTQuanT);
    conv->quanParameter->type = 3;
    conv->external = {3793581568, 1271398400, 0, 0, 0};
    net.oplists.push_back(std::move(head));
    if (withReshape) {
        auto reshape = std::unique_ptr<MNN::OpT>(new MNN::OpT);
        reshape->name = "/lm/lm_head/Linear/post_reshape";
        reshape->type = MNN::OpType_Reshape;
        reshape->main.Set(MNN::ReshapeT{});
        reshape->main.AsReshape()->dims = {1, -1, reshapeOutputs};
        net.oplists.push_back(std::move(reshape));
    }
    flatbuffers::FlatBufferBuilder builder;
    builder.Finish(MNN::Net::Pack(builder, &net));
    std::ofstream output(path, std::ios::binary);
    output.write(reinterpret_cast<const char*>(builder.GetBufferPointer()), builder.GetSize());
}

int main(int argc, char** argv) {
    assert(argc == 3);
    const std::string directory = argv[1];
    const std::string mode = argv[2];
    std::vector<int8_t> rows(255 * 2560 * 2);
    for (size_t index = 0; index < rows.size(); ++index) rows[index] = static_cast<int8_t>(index % 127);
    {
        std::ofstream selected(directory + "/selected.bin", std::ios::binary);
        selected.write(reinterpret_cast<const char*>(rows.data()), rows.size());
    }
    if (mode != "verify") {
        writeGraph(directory + "/source.mnn", mode == "bad-head" ? 255 : 248320,
                   mode != "no-reshape", mode == "bad-reshape" ? 123 : 248320);
        if (mode == "truncated") {
            std::ofstream truncated(directory + "/selected.bin", std::ios::binary);
            truncated << 'x';
        }
        if (mode == "malformed") {
            std::ofstream malformed(directory + "/source.mnn", std::ios::binary);
            malformed << std::string(16, '\0');
        }
        return 0;
    }
    std::ifstream output(directory + "/output.mnn", std::ios::binary);
    std::vector<char> bytes((std::istreambuf_iterator<char>(output)), {});
    std::unique_ptr<MNN::NetT> compact(MNN::GetNet(bytes.data())->UnPack());
    const auto* conv = compact->oplists[0]->main.AsConvolution2D();
    assert(conv->common->outputCount == 255);
    assert(conv->external.empty());
    assert(conv->quanParameter->type == 3 && conv->quanParameter->buffer == rows);
    assert(conv->bias == std::vector<float>(255, 0.0f));
    assert(compact->oplists[1]->main.AsReshape()->dims == std::vector<int32_t>({1, -1, 255}));
    std::cout << "PASS compact output rows, FP16 bytes, zero bias and reshape\n";
}
