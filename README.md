# Turbo AI Chat

[English](README_EN.md) | 中文

![Turbo AI Chat hero](docs/images/hero.png)

**HarmonyOS NEXT 原生端侧大模型聊天应用**。基于 ArkTS + C++ N-API + MNN Runtime，在设备本地运行 Qwen3-4B-Instruct（默认文本）、MiniCPM5-1B（文本）和 Gemma-4-E2B-it（多模态）模型，支持流式对话、模型切换、内置模型一键下载。

本仓库 fork 自 [Turbo1123/turbo-ai-chat-harmonyos](https://github.com/Turbo1123/turbo-ai-chat-harmonyos)。

## 项目背景

鸿蒙生态中，端侧 AI 推理目前主要依赖卓易通等 Android 兼容层运行安卓 App。Turbo AI Chat 用纯原生链路（ArkTS → N-API → MNN → CPU）验证了一条不同的路径：

- **架构原生**：推理层直接对接 HarmonyOS NDK，无 Android 兼容层转译开销
- **开箱可复现**：内置模型从 ModelScope 一键下载，不依赖 HuggingFace（国内网络友好）
- **工程可复用**：MNN Runtime 封装、流式输出管线、Markdown 渲染等模块可作为其他鸿蒙 AI 应用的集成参考
- **开发者友好**：hdc 一键查看原始推理日志（`raw_output_debug.txt`），包含 prompt、模型输出、采样参数和 token 统计，便于定位模型行为

  ```sh
  hdc shell "cat /data/app/el2/100/base/com.example.gemma4mnn/haps/entry/files/raw_output_debug.txt"
  ```

如果你正在探索「鸿蒙 + 本地 AI」的技术方案，这个项目提供了一个可验证的工程基线。

## 近期重要改进

- 默认文本模型切换为 Qwen3-4B-Instruct，并支持在 App 内从 ModelScope 安装 Qwen3-4B-Instruct、MiniCPM5-1B 和 Gemma-4-E2B-it。
- 模型导入流程更完整：除 zip 导入外，支持将完整 MNN 模型目录推送到 App 沙箱后，在模型页一键扫描注册，适合绕过大 zip 导入失败的问题。
- 模型页和运行配置更稳健：模型生成、加载、导入期间会禁用相关控件，避免推理中途修改参数造成状态不一致。
- 聊天页新增设备状态条，可快速查看应用 CPU、应用内存和设备温度等运行状态。
- 监控页新增 App 存储占用、模型状态和更紧凑的设备指标展示。
- 优化 Markdown 渲染、列表解析、思考块展示和原始输出日志，便于排查模型复读、停止符和模板问题。

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

App 和 HAP 均不内置模型权重。打开 App → 模型页 → 选 Qwen3-4B-Instruct、MiniCPM5-1B 或 Gemma-4-E2B-it → 加载，App 自动引导从 ModelScope 下载到沙箱。

| 模型 | 大小 | 能力 |
|------|------|------|
| Qwen3-4B-Instruct | ~2.5 GB | 文本 |
| Gemma-4-E2B-it | ~3.7 GB | 文本 + 图片 |
| MiniCPM5-1B (BF16) | ~2.1 GB | 文本 |

### 3. 开始聊天

模型加载完成后回到聊天页，发送消息即可。Qwen3-4B-Instruct 是默认文本模型，MiniCPM5-1B 会展示思考块（`<think>`），Gemma-4-E2B-it 支持图片输入。

## 功能

- 本地推理：模型在设备端运行，无网络依赖
- 流式输出：token 级实时响应
- 模型切换：Qwen3-4B-Instruct / MiniCPM5-1B / Gemma-4-E2B-it 热切换
- 思考块：MiniCPM5-1B 展示推理思考过程
- Markdown 渲染：代码块（含复制按钮）、表格、引用、链接等
- 生成参数调节：温度、Top-P/K、惩罚项等
- 性能指标：TTFT、TPOT、tokens/s 实时显示
- 内置模型管理：一键下载、安装、更新
- 导入本地 MNN 模型：支持 zip 导入，也支持 hdc 推送目录后扫描注册

## 截图

| 聊天界面                          | 模型界面                              | 监控界面                                |
|-------------------------------|-----------------------------------|-------------------------------------|
| ![chat](docs/images/chat.jpg) | ![models](docs/images/models.jpg) | ![monitor](docs/images/monitor.jpg) |

## 从 HAP 直接安装

[Releases](https://github.com/Torry2022/turbo-ai-chat-harmonyos/releases) 提供签名 HAP。使用 hdc 安装：

```sh
hdc install -r turbo-ai-chat-harmonyos-vX.Y.Z-signed.hap
```

也可通过[小白调试助手](https://github.com/likuai2010/auto-installer)图形化安装。调试签名包仅限当前 profile 内设备；其他设备请下载未签名包自行签名。

## 手动推送模型目录

App 内下载内置模型、App 内选择 zip 导入模型是推荐方式。以下 `hdc` 推送仅作调试备用。

推送的模型目录必须是 **MNN 格式**，即通过 MNN `llmexport.py` 从 HuggingFace 权重导出的目录，包含 `config.json`、`llm_config.json`、tokenizer 文件、`llm.mnn`、`llm.mnn.weight` 等。原始 HuggingFace safetensors、GGUF、MLX 权重不能直接使用。

### 内置模型目录备用推送

以下命令用于补齐 App 已内置在模型列表中的模型目录，是 App 内下载失败或离线调试时的备用方案。

```sh
cd models
hdc file send -b com.example.gemma4mnn gemma-4-E2B-it-MNN /data/storage/el2/base/haps/entry/files/
hdc file send -b com.example.gemma4mnn MiniCPM5-1B-MNN /data/storage/el2/base/haps/entry/files/
hdc file send -b com.example.gemma4mnn Qwen3-4B-Instruct-2507-MNN /data/storage/el2/base/haps/entry/files/
```

> `-b` 指定 bundle 名称，是写入 App 沙箱的必需参数。

### 导入模型目录手动推送

如果 App 内导入大 zip 包失败，可以绕过 zip 解压，直接用 `hdc` 推送 MNN 模型目录，并在 App 内扫描注册。

**要注册为导入模型**：

1. 准备一个完整的 MNN 模型目录。目录中应包含 `config.json`、`llm_config.json`、`llm.mnn`、`llm.mnn.weight`、tokenizer 文件等。
2. 建议把该目录放到仓库的 `models/` 目录下，例如 `models/Qwen3-4B-Instruct-2507-MNN`。
3. 从模型目录的父目录执行推送命令：

   ```sh
   cd models
   hdc file send -b com.example.gemma4mnn Qwen3-4B-Instruct-2507-MNN /data/storage/el2/base/haps/entry/files/model-imports/
   ```

4. 查看真机沙箱中的目录结构，确认关键文件完整：

   ```sh
   hdc shell "ls -la /data/app/el2/100/base/com.example.gemma4mnn/haps/entry/files/model-imports/Qwen3-4B-Instruct-2507-MNN"
   ```

   目录中应能看到 `config.json`、`llm_config.json`、`llm.mnn`、`llm.mnn.weight` 和 tokenizer 文件。

5. 打开 App → 模型页 → 展开“模型管理”。
6. 点击“扫描已推送目录”。App 会自动查找 `config.json` 和 `.mnn` 文件，生成导入模型配置并保存到 `model-imports/imported-models.json`。
7. 在模型列表中选择新增的导入模型并加载。

扫描只识别 `model-imports/` 下的一级子目录；目录名不要包含 `/`、`\` 或 `..`。在 Windows 终端中建议从模型目录的父目录执行 `hdc file send`，避免把更多上级路径或反斜杠写入 App 沙箱。若你的模型不在仓库 `models/` 下，也可以 `cd` 到该模型目录的父目录后再推送。

## PC 侧下载模型脚本

```sh
# Qwen3-4B-Instruct（约 2.5 GB）
./scripts/download_qwen3_4b_mnn.sh

# Gemma-4-E2B-it（约 3.7 GB）
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

App 使用 **MNN 模型目录**格式。内置模型当前从 ModelScope 下载：Qwen3-4B-Instruct 和 Gemma-4-E2B-it 来自 [MNN 官方](https://modelscope.cn/organization/MNN)，MiniCPM5-1B BF16 来自 [TorryJi](https://modelscope.cn/models/TorryJi/MiniCPM5-1B-MNN-BF16)。原始 HuggingFace 权重需要经 MNN `llmexport.py` 转换后才能使用。

## 原生接口

ArkTS 通过 `import entry from 'libentry.so'` 调用 N-API：

```ts
entry.loadModelAsync(configPath, threadNum, maxNewTokens, settings): Promise<string>
entry.generateRawPromptStream(prompt, maxNewTokens, endWith, settings, onChunk): Promise<GenerationResult>
entry.generateChatStream(messages, maxNewTokens, settings, onChunk): Promise<GenerationResult>
entry.reset(): void
entry.isLoaded(): boolean
```

## 许可证

Apache-2.0. MNN 和模型文件遵循各自上游许可证。本仓库不提交模型权重。
