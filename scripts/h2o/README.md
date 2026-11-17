# H2O-Lightning 决策封装

[简体中文](README.md) | [English](README_EN.md)

基于 MNN LLM Runtime 调用 H2O-Lightning-4B，提供模型加载、文本与单张图片决策、候选概率读取和释放接口。采用官方 v1.4.2 的 causal 路径，提示词、255 个候选标签及分类温度与该版本的 `serve_config.json` 对齐。

## 构建

将 `h2o_decision.cpp` 和 `h2o_protocol.cpp` 加入调用工程的 Native 编译目标，将本目录和项目的 `third_party/mnn/include` 加入头文件搜索路径，链接 `libMNN.so`。使用 C++17。`h2o_contract.h` 记录对应模型版本的提示词与标签。

运行时传入完整 MNN 模型目录内的 `config.json` 路径。目录须包含主干、输出层、词嵌入、分词器和运行配置，图片调用还需要视觉模型。加载会校验全部候选标签的 token ID 是否与官方分词器一致。

支持完整词表输出包和 255 个候选标签的输出包。候选输出包在 `config.json` 中设置 `"decision_output": "h2o-labels-v1"`，输出顺序与 `h2o_contract.h` 中的 `labelTokens` 一致。封装按该映射读取结果，并校验输出数量。完整词表输出包沿用 token ID 索引。

本封装使用 CPU，默认 4 线程，`precision=normal`、`memory=low`、`dynamic_option=2`，与本轮 INT8 验证配置一致。加载和推理应在后台工作线程执行。

### 缩小决策输出层

`compact_model.py` 可将本项目原始 INT8 包转换为候选输出包，降低输出层加载的内存需求。它校验源文件哈希，直接提取官方 255 个标签对应的 FP16 权重行，并移除权重文件末尾的完整输出层。需要 Python 3.11 或更高版本、C++ 编译器和对应版本的 MNN 源码目录。

```sh
python scripts/h2o/compact_model.py --source /path/to/original-model \
    --output /path/to/compact-model --mnn-source /path/to/MNN
```

输出目录需尚未存在。生成的目录包含模型、运行配置、转换信息和 SHA-256 校验清单，使用候选输出包时须配套本版决策封装。

## 文本决策

```cpp
#include "h2o_decision.h"

H2o::DecisionModel model;
model.load(modelDirectory + "/config.json");

H2o::Question question;
question.type = H2o::QuestionType::Choice;
question.state = "客户已付款，订单仍显示待支付。";
question.instruction = "这个问题应交给哪个团队？";
question.options = {
    {"payment", "支付与订单团队"},
    {"shipping", "物流配送团队"}
};
auto result = model.decide(question);
const auto& selectedName = result.options[result.selectedIndex].name;
model.release();
```

`options` 保持调用方给出的顺序。Choice 使用唯一名称及说明，Noul 使用 `true`、`false` 两项，也可留空采用官方默认说明。Score 使用从 `0` 开始的连续等级名称和各级说明。

## 图片决策

```cpp
H2o::Image image;
image.width = width;
image.height = height;
image.rgb = rgbPixels;
auto result = model.decide(question, &image);
```

图片输入为连续排列的 RGB 字节，每像素三字节，无行尾填充。内部完成 MNN 所需的通道转换，缩放由模型的视觉配置处理。图片问题使用官方的温度 `1.0`。文本参数中不能直接嵌入 MNN 媒体路径标记。

## 返回结果与生命周期

- `probabilities` 与 `options` 顺序一致，总和为 1。Noul 的第一个值为肯定概率。
- `selectedIndex` 为最高概率候选项的位置，并列时取第一个。
- Score 的 `score` 为各等级按概率加权的期望值，可以是小数。
- Choice 的 `confidence` 沿用官方归一化最高概率，均匀分布为 0，单点分布为 1。Score 的该值为最高等级概率。Noul 应读取肯定概率。
- `inputTokens` 为最终输入 token 数。`preprocessingMs` 包含分词和图片视觉编码，`forwardMs` 为语言模型前向及候选 logits 读取耗时。

每题独立重置上下文。默认完整输入上限为 40,960 tokens，可在 `load` 的第三个参数中调低。超限会抛出异常，调用方可缩短输入后重试。

同一实例的加载、决策和释放通过互斥锁串行执行，释放会等待正在执行的决策完成。重复加载要求先释放，重复释放安全。加载失败不会留下已加载状态。实例析构自动释放模型，调用方应先结束使用该实例的工作线程。

## 协议检查

候选输出层的转换检查覆盖权重字节、零偏置、输出形状和异常输入。

```sh
python scripts/h2o/tests/test_compact_output.py --mnn-source /path/to/MNN
```

以下检查不需要模型权重，可在有 C++17 编译器的主机运行。

```sh
g++ -std=c++17 -Wall -Wextra -Werror -I scripts/h2o \
    scripts/h2o/h2o_protocol.cpp scripts/h2o/tests/protocol_test.cpp \
    -o h2o_protocol_test
./h2o_protocol_test
```

模型及调用约定来源于 [H2O 官方模型仓库](https://huggingface.co/h2oai/h2o-lightning-4b/tree/659fc412de8486dbc2477b0d1cb4121e97e72471)。
