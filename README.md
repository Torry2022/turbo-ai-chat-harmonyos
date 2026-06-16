# Turbo AI Chat

[English](README_EN.md) | 中文

![Turbo AI Chat hero](docs/images/hero.png)

**HarmonyOS NEXT 原生端侧大模型聊天应用**。基于 ArkTS + C++ N-API + MNN Runtime，在设备本地运行 Gemma 4 E2B（多模态）和 MiniCPM5-1B（文本）模型，支持流式对话、模型切换、内置模型一键下载。

本仓库 fork 自 [Turbo1123/turbo-ai-chat-harmonyos](https://github.com/Turbo1123/turbo-ai-chat-harmonyos)。

## 项目背景

鸿蒙生态中，端侧 AI 推理目前主要依赖卓易通等 Android 兼容层运行安卓 App。Turbo AI Chat 用纯原生链路（ArkTS → N-API → MNN → CPU）验证了一条不同的路径：

- **架构原生**：推理层直接对接 HarmonyOS NDK，无 Android 兼容层转译开销
- **开箱可复现**：内置模型从 ModelScope 一键下载，不依赖 HuggingFace（国内网络友好）
- **工程可复用**：MNN Runtime 封装、流式输出管线、Markdown 渲染等模块可作为其他鸿蒙 AI 应用的集成参考
- **开发者友好**：hdc 一键查看原始推理日志（`raw_output_debug.txt`），便于定位模型行为

如果你正在探索「鸿蒙 + 本地 AI」的技术方案，这个项目提供了一个可验证的工程基线。

## 快速开始

### 1. 克隆并构建

```sh
git clone https://github.com/Torry2022/turbo-ai-chat-harmonyos.git
cd turbo-ai-chat-harmonyos
```

用 DevEco Studio 打开项目，登录华为开发者账号，开启自动签名，然后运行到真机。或命令行：

```sh
node ./node_modules/@ohos/hvigor/bin/hvigor.js assembleHap --no-daemon
hdc install -r entry/build/default/outputs/default/entry-default-signed.hap
```

### 2. 安装内置模型

App 和 HAP 均不内置模型权重。打开 App → 模型页 → 选 Gemma 4 或 MiniCPM5-1B → 加载，App 自动引导从 ModelScope 下载到沙箱。

| 模型 | 大小 | 能力 |
|------|------|------|
| Gemma 4 E2B | ~3.7 GB | 文本 + 图片 |
| MiniCPM5-1B (BF16) | ~2.1 GB | 文本 |

### 3. 开始聊天

模型加载完成后回到聊天页，发送消息即可。MiniCPM5-1B 会展示思考块（`<think>`），Gemma 4 支持图片输入。

## 功能

- 本地推理：模型在设备端运行，无网络依赖
- 流式输出：token 级实时响应
- 模型切换：Gemma 4 / MiniCPM5-1B 热切换
- 思考块：MiniCPM5-1B 展示推理思考过程
- Markdown 渲染：代码块（含复制按钮）、表格、引用、链接等
- 生成参数调节：温度、Top-P/K、惩罚项等
- 性能指标：TTFT、TPOT、tokens/s 实时显示
- 内置模型管理：一键下载、安装、更新
- 导入本地 MNN zip：支持自有模型包导入

## 截图

| 聊天界面                          | 模型界面                              | 监控界面                                |
|-------------------------------|-----------------------------------|-------------------------------------|
| ![chat](docs/images/chat.jpg) | ![models](docs/images/models.jpg) | ![monitor](docs/images/monitor.jpg) |

## 从 HAP 直接安装

[Releases](https://github.com/Torry2022/turbo-ai-chat-harmonyos/releases) 提供签名 HAP。使用 hdc 安装：

```sh
hdc install -r turbo-ai-chat-harmonyos-v0.2.0-signed.hap
```

也可通过[小白调试助手](https://github.com/likuai2010/auto-installer)图形化安装。调试签名包仅限当前 profile 内设备；其他设备请下载未签名包自行签名。

## 备用：手动推送模型

App 内下载是推荐方式。以下 `hdc` 推送仅作调试备用。

推送的模型目录必须是 **MNN 格式**，即通过 MNN `llmexport.py` 从 HuggingFace 权重导出的目录，包含 `config.json`、`llm_config.json`、`tokenizer.mtok`、`llm.mnn`、`llm.mnn.weight` 等文件。原始 HuggingFace safetensors、GGUF、MLX 权重不能直接使用。

```sh
hdc file send -b com.example.gemma4mnn models/gemma-4-E2B-it-MNN /data/storage/el2/base/haps/entry/files/
hdc file send -b com.example.gemma4mnn models/MiniCPM5-1B-MNN /data/storage/el2/base/haps/entry/files/
```

> `-b` 指定 bundle 名称，是写入 App 沙箱的必需参数。超过约 2 GB 的 zip 包可能因系统 ZIP 兼容性问题导入失败，建议用 `file send` 直接推送目录。

## PC 侧下载模型脚本

```sh
# Gemma 4 E2B（约 3.7 GB）
./scripts/download_gemma4_e2b_mnn.sh

# MiniCPM5-1B BF16（约 2.1 GB）
./scripts/download_minicpm5_1b_mnn.sh
```

指定输出目录：

```sh
./scripts/download_minicpm5_1b_mnn.sh /path/to/MiniCPM5-1B-MNN
```

需要 Python modelscope 包：`pip install modelscope`。

## 模型格式说明

App 使用 **MNN 模型目录**格式。内置模型当前从 [TorryJi/MiniCPM5-1B-MNN-BF16](https://modelscope.cn/models/TorryJi/MiniCPM5-1B-MNN-BF16)（ModelScope）和 MNN 官方 Gemma 4 源下载。原始 HuggingFace 权重需要经 MNN `llmexport.py` 转换后才能使用。

## 原生接口

ArkTS 通过 `import entry from 'libentry.so'` 调用 N-API：

```ts
entry.loadModelAsync(configPath, threadNum, maxNewTokens, settings): Promise<string>
entry.generateRawPromptStream(prompt, maxNewTokens, endWith, settings, onChunk): Promise<GenerationResult>
entry.generateChatStream(messages, maxNewTokens, settings, onChunk): Promise<GenerationResult>
entry.reset(): void
entry.isLoaded(): boolean
```

## License

Apache-2.0. MNN 和模型文件遵循各自上游许可证。本仓库不提交模型权重。
