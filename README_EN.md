# Turbo AI Chat

[中文](README.md) | English

![Turbo AI Chat hero](docs/images/hero.png)

**HarmonyOS NEXT native on-device LLM chat application**. Built with ArkTS + C++ N-API + MNN Runtime, running Qwen3-4B-Instruct (text), MiniCPM5-1B (text), and Gemma 4 E2B (multimodal) locally on HarmonyOS devices with streaming chat, model switching, and one-click built-in model download.

This repository is forked from [Turbo1123/turbo-ai-chat-harmonyos](https://github.com/Turbo1123/turbo-ai-chat-harmonyos).

## Background

In the HarmonyOS ecosystem, on-device AI inference today largely depends on Android compatibility layers running Android apps. Turbo AI Chat validates a different path with a fully native pipeline (ArkTS → N-API → MNN → CPU):

- **Native architecture**: inference directly via HarmonyOS NDK, no Android compatibility layer overhead
- **Reproducible out of the box**: built-in models downloaded from ModelScope with one click, no HuggingFace required (China-network friendly)
- **Reusable engineering**: MNN Runtime wrapper, streaming pipeline, Markdown rendering as integration references for other HarmonyOS AI apps
- **Developer-friendly**: one hdc command to inspect raw inference logs (`raw_output_debug.txt`)

## Quick Start

### 1. Clone and build

```sh
git clone https://github.com/Torry2022/turbo-ai-chat-harmonyos.git
cd turbo-ai-chat-harmonyos
```

Open with DevEco Studio, log in to your Huawei developer account, enable automatic signing, then run on a device. Or via command line:

```sh
node ./node_modules/@ohos/hvigor/bin/hvigor.js assembleHap --no-daemon
hdc install -r entry/build/default/outputs/default/entry-default-signed.hap
```

### 2. Install built-in models

The app and HAP do not include model weights. Open the app → Model tab → select Qwen3, MiniCPM5-1B, or Gemma 4 → load. The app will guide you to download from ModelScope into the app sandbox.

| Model | Size | Capability |
|------|------|------|
| Qwen3-4B-Instruct | ~2.5 GB | Text |
| Gemma 4 E2B | ~3.7 GB | Text + Image |
| MiniCPM5-1B (BF16) | ~2.1 GB | Text |

### 3. Start chatting

After the model loads, return to the Chat tab and send a message. MiniCPM5-1B displays thinking blocks (`<think>`). Gemma 4 supports image input.

## Features

- Local inference: models run on-device, no network required
- Streaming output: token-level real-time response
- Model switching: Qwen3 / MiniCPM5-1B / Gemma 4 hot swap
- Thinking blocks: MiniCPM5-1B displays reasoning process
- Markdown rendering: code blocks (with copy button), tables, blockquotes, links, etc.
- Generation parameter controls: temperature, Top-P/K, penalty terms, etc.
- Performance metrics: TTFT, TPOT, tokens/s per assistant message
- Built-in model management: one-click download, install, update
- Import local MNN zip packages

## Screenshots

| Chat | Model | Monitor |
| --- | --- | --- |
| ![chat](docs/images/chat.jpg) | ![models](docs/images/models.jpg) | ![monitor](docs/images/monitor.jpg) |

## Install from HAP

[Releases](https://github.com/Torry2022/turbo-ai-chat-harmonyos/releases) provide signed HAPs. Install via hdc:

```sh
hdc install -r turbo-ai-chat-harmonyos-v1.0.0-signed.hap
```

You can also use [Xiaobai Debug Assistant](https://github.com/likuai2010/auto-installer) for graphical installation. The signed HAP only works on devices within the current debug signing profile. For other devices, download the unsigned HAP and re-sign with your own developer account.

## Fallback: Manual Model Push

In-app download and zip import are the recommended approaches. Manual `hdc` push is kept as a debugging fallback.

The model directory must be in **MNN format** — exported via MNN `llmexport.py` from HuggingFace weights, containing `config.json`, `llm_config.json`, tokenizer file, `llm.mnn`, `llm.mnn.weight`, etc. Original HuggingFace safetensors, GGUF, and MLX weights cannot be used directly.

### Pushing built-in model directories

Use the following commands to restore built-in model directories when in-app download is unavailable:

```sh
hdc file send -b com.example.gemma4mnn models/gemma-4-E2B-it-MNN /data/storage/el2/base/haps/entry/files/
hdc file send -b com.example.gemma4mnn models/MiniCPM5-1B-MNN /data/storage/el2/base/haps/entry/files/
hdc file send -b com.example.gemma4mnn models/Qwen3-4B-Instruct-2507-MNN /data/storage/el2/base/haps/entry/files/
```

> The `-b` flag specifies the bundle name and is required to write into the app sandbox. Zip files larger than ~2 GB may fail due to system ZIP compatibility — use `file send` to push the directory directly instead.

### Pushing a model for manual path loading

Push model files to any subdirectory, then expand "Runtime Config" on the Model page and set the config path to `config.json` in that directory. This loads the model without registering it as an import entry.

```sh
hdc file send -b com.example.gemma4mnn models/Qwen3-4B-Instruct-2507-MNN /data/storage/el2/base/haps/entry/files/manual-models/
```

In the app, set the model config path to:

```text
/data/storage/el2/base/haps/entry/files/manual-models/Qwen3-4B-Instruct-2507-MNN/config.json
```

### Registering a pushed model as an import

To have a manually pushed model appear in the import model list, push the directory under `model-imports/`, then write a matching entry in `imported-models.json`. See the Chinese README for the full JSON template and detailed steps.

## PC-side Model Download Scripts

```sh
# Qwen3-4B-Instruct (~2.5 GB)
./scripts/download_qwen3_4b_mnn.sh

# Gemma 4 E2B (~3.7 GB)
./scripts/download_gemma4_e2b_mnn.sh

# MiniCPM5-1B BF16 (~2.1 GB)
./scripts/download_minicpm5_1b_mnn.sh
```

Specify an output directory:

```sh
./scripts/download_minicpm5_1b_mnn.sh /path/to/MiniCPM5-1B-MNN
```

Requires the Python modelscope package: `pip install modelscope`.

## Model Format

The app uses **MNN model directory** format. Built-in models are downloaded from ModelScope: Qwen3-4B-Instruct and Gemma 4 E2B from the [MNN organization](https://modelscope.cn/organization/MNN), MiniCPM5-1B BF16 from [TorryJi](https://modelscope.cn/models/TorryJi/MiniCPM5-1B-MNN-BF16). Original HuggingFace weights must be converted via MNN `llmexport.py` before use.

## Native API

ArkTS calls N-API via `import entry from 'libentry.so'`:

```ts
entry.loadModelAsync(configPath, threadNum, maxNewTokens, settings): Promise<string>
entry.generateRawPromptStream(prompt, maxNewTokens, endWith, settings, onChunk): Promise<GenerationResult>
entry.generateChatStream(messages, maxNewTokens, settings, onChunk): Promise<GenerationResult>
entry.reset(): void
entry.isLoaded(): boolean
```

## License

Apache-2.0. MNN and model files follow their respective upstream licenses. This repository does not commit model weights.
