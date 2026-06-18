# Turbo AI Chat

[English](README_EN.md) | 中文

![Turbo AI Chat hero](docs/images/hero.png)

**HarmonyOS NEXT 原生端侧大模型聊天应用**。基于 ArkTS + C++ N-API + MNN Runtime，在设备本地运行 Qwen3-4B-Instruct（默认文本）、MiniCPM5-1B（文本）和 Gemma 4 E2B（多模态）模型，支持流式对话、模型切换、内置模型一键下载。

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

App 和 HAP 均不内置模型权重。打开 App → 模型页 → 选 Qwen3、MiniCPM5-1B 或 Gemma 4 → 加载，App 自动引导从 ModelScope 下载到沙箱。

| 模型 | 大小 | 能力 |
|------|------|------|
| Qwen3-4B-Instruct | ~2.5 GB | 文本 |
| Gemma 4 E2B | ~3.7 GB | 文本 + 图片 |
| MiniCPM5-1B (BF16) | ~2.1 GB | 文本 |

### 3. 开始聊天

模型加载完成后回到聊天页，发送消息即可。Qwen3-4B-Instruct 是默认文本模型，MiniCPM5-1B 会展示思考块（`<think>`），Gemma 4 支持图片输入。

## 功能

- 本地推理：模型在设备端运行，无网络依赖
- 流式输出：token 级实时响应
- 模型切换：Qwen3 / MiniCPM5-1B / Gemma 4 热切换
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
hdc install -r turbo-ai-chat-harmonyos-v1.0.0-signed.hap
```

也可通过[小白调试助手](https://github.com/likuai2010/auto-installer)图形化安装。调试签名包仅限当前 profile 内设备；其他设备请下载未签名包自行签名。

## 备用：手动推送模型

App 内下载内置模型、App 内选择 zip 导入模型是推荐方式。以下 `hdc` 推送仅作调试备用。

推送的模型目录必须是 **MNN 格式**，即通过 MNN `llmexport.py` 从 HuggingFace 权重导出的目录，包含 `config.json`、`llm_config.json`、tokenizer 文件、`llm.mnn`、`llm.mnn.weight` 等。原始 HuggingFace safetensors、GGUF、MLX 权重不能直接使用。

### 内置模型目录备用推送

以下命令用于补齐 App 已内置在模型列表中的模型目录。它不是“导入模型 zip 包”的流程，只是 App 内下载失败或离线调试时的备用方案。

```sh
hdc file send -b com.example.gemma4mnn models/gemma-4-E2B-it-MNN /data/storage/el2/base/haps/entry/files/
hdc file send -b com.example.gemma4mnn models/MiniCPM5-1B-MNN /data/storage/el2/base/haps/entry/files/
hdc file send -b com.example.gemma4mnn models/Qwen3-4B-Instruct-2507-MNN /data/storage/el2/base/haps/entry/files/
```

> `-b` 指定 bundle 名称，是写入 App 沙箱的必需参数。

### 导入模型目录手动推送

如果 App 内导入大 zip 包失败，可以绕过 zip 解压，直接用 `hdc` 推送 MNN 模型目录。这里有两种用法：

**只想临时加载测试**：把模型目录推到沙箱任意子目录，然后在模型页展开“运行配置”，把“模型配置路径”改为该目录下的 `config.json`，再点击“加载模型”。这种方式不会把模型加入“导入模型”列表，也不会保存为可编辑/可删除的导入模型项。

```sh
hdc file send -b com.example.gemma4mnn models/Qwen3-4B-Instruct-2507-MNN /data/storage/el2/base/haps/entry/files/manual-models/
```

App 中填写：

```text
/data/storage/el2/base/haps/entry/files/manual-models/Qwen3-4B-Instruct-2507-MNN/config.json
```

**要注册为导入模型**：仅推送模型目录是不够的；App 的“导入模型”列表依赖 `model-imports/imported-models.json`。以下示例把本机 `models/Qwen3-4B-Instruct-2507-MNN` 注册为一个用户导入模型。`imported-qwen3-4b` 是自定义目录名和模型 id，只能使用普通目录名，不要包含 `/`、`\` 或 `..`。

```sh
hdc shell "mkdir -p /data/app/el2/100/base/com.example.gemma4mnn/haps/entry/files/model-imports"
hdc file send -b com.example.gemma4mnn models/Qwen3-4B-Instruct-2507-MNN /data/storage/el2/base/haps/entry/files/model-imports/imported-qwen3-4b/
```

然后在 PC 侧创建 `imported-models.json`：

```json
{
  "models": [
    {
      "id": "imported-qwen3-4b",
      "name": "Qwen3-4B-Instruct",
      "shortName": "Qwen3-4B",
      "directoryName": "imported-qwen3-4b",
      "description": "用户手动推送的 MNN 模型。",
      "supportsImage": false,
      "systemPrompt": "你是本地 AI 助手。请始终使用简体中文回答，表达简洁清楚；只回答用户最新问题；不要重复同一句话。",
      "source": "imported",
      "configPath": "/data/storage/el2/base/haps/entry/files/model-imports/imported-qwen3-4b/config.json",
      "chatFormat": "mnn-auto",
      "promptTemplate": "",
      "stopSequence": "",
      "templateOverride": false,
      "editable": true,
      "removable": true
    }
  ]
}
```

再把清单推送到 App 沙箱：

```sh
hdc file send -b com.example.gemma4mnn imported-models.json /data/storage/el2/base/haps/entry/files/model-imports/imported-models.json
```

重启 App 后，模型页会读取该清单并显示这个导入模型。若设备上已经有其他导入模型，不要直接覆盖 `imported-models.json`；应先取回现有清单并把新模型追加到 `models` 数组中。

## PC 侧下载模型脚本

```sh
# Qwen3-4B-Instruct（约 2.5 GB）
./scripts/download_qwen3_4b_mnn.sh

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

App 使用 **MNN 模型目录**格式。内置模型当前从 ModelScope 下载：Qwen3-4B-Instruct 和 Gemma 4 E2B 来自 [MNN 官方](https://modelscope.cn/organization/MNN)，MiniCPM5-1B BF16 来自 [TorryJi](https://modelscope.cn/models/TorryJi/MiniCPM5-1B-MNN-BF16)。原始 HuggingFace 权重需要经 MNN `llmexport.py` 转换后才能使用。

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
