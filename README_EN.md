# Turbo AI Chat

[中文](README.md) | English

![Turbo AI Chat hero](docs/images/hero.png)

**HarmonyOS NEXT native on-device LLM chat application**. Built with ArkTS + C++ N-API + MNN Runtime, running Qwen3-4B-Instruct (text), MiniCPM5-1B (text), and Gemma-4-E2B-it (multimodal) locally on HarmonyOS devices with streaming chat, model switching, and one-click built-in model download.

This repository is forked from [Turbo1123/turbo-ai-chat-harmonyos](https://github.com/Turbo1123/turbo-ai-chat-harmonyos).

## Background

In the HarmonyOS ecosystem, on-device AI inference today largely depends on Android compatibility layers running Android apps. Turbo AI Chat validates a different path with a fully native pipeline (ArkTS → N-API → MNN → CPU):

- **Native architecture**: inference directly via HarmonyOS NDK, no Android compatibility layer overhead
- **Reproducible out of the box**: built-in models downloaded from ModelScope with one click, no HuggingFace required (China-network friendly)
- **Reusable engineering**: MNN Runtime wrapper, streaming pipeline, Markdown rendering as integration references for other HarmonyOS AI apps
- **Developer-friendly**: one hdc command to inspect raw inference logs (`raw_output_debug.txt`) containing prompt, model output, sampling parameters, and token statistics

  ```sh
  hdc shell "cat /data/app/el2/100/base/com.example.gemma4mnn/haps/entry/files/raw_output_debug.txt"
  ```

## Recent Highlights

- Switched the default text model to Qwen3-4B-Instruct, with in-app ModelScope installation for Qwen3-4B-Instruct, MiniCPM5-1B, and Gemma-4-E2B-it.
- Improved model import: in addition to zip import, you can push a complete MNN model directory into the app sandbox and scan it from the Model tab, which avoids large zip import failures.
- Made model-page controls safer by disabling relevant actions while loading, importing, or generating; model ordering and deleting installed model directories are also supported.
- Added generation interruption: during streaming output, the send button switches to a stop button, and stopped responses are not added to future conversation context.
- Added a device status strip on the Chat tab for app CPU, app memory, and device temperature.
- Added app storage usage, model state, and tighter device metrics to the Monitor tab.
- Improved Markdown rendering, list parsing, thinking block display, raw output logs, and MNN chat-template handling for diagnosing repetition, stop tokens, and prompt template issues.

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

The app and HAP do not include model weights. Open the app → Model tab → select Qwen3-4B-Instruct, MiniCPM5-1B, or Gemma-4-E2B-it → load. The app will guide you to download from ModelScope into the app sandbox.

| Model | Size | Capability |
|------|------|------|
| Qwen3-4B-Instruct | ~2.5 GB | Text |
| Gemma-4-E2B-it | ~3.7 GB | Text + Image |
| MiniCPM5-1B (BF16) | ~2.1 GB | Text |

### 3. Start chatting

After the model loads, return to the Chat tab and send a message. MiniCPM5-1B displays thinking blocks (`<think>`). Gemma-4-E2B-it supports image input.

## Features

- Local inference: models run on-device, no network required
- Streaming output: token-level real-time response
- Stop generation: interrupt the current response while it is streaming
- Model switching: Qwen3-4B-Instruct / MiniCPM5-1B / Gemma-4-E2B-it hot swap
- Thinking blocks: MiniCPM5-1B displays reasoning process
- Markdown rendering: code blocks (with copy button), tables, blockquotes, links, etc.
- Generation parameter controls: temperature, Top-P/K, penalty terms, etc.
- Performance metrics: TTFT, TPOT, tokens/s per assistant message
- Model management: one-click built-in model download, model ordering, and deleting installed model directories
- Import local MNN models via zip, or by pushing a directory and scanning it in the app; standard MNN export directories use `jinja.chat_template` from `llm_config.json`

## Screenshots

| Chat | Model | Monitor |
| --- | --- | --- |
| ![chat](docs/images/chat.jpg) | ![models](docs/images/models.jpg) | ![monitor](docs/images/monitor.jpg) |

## Install from HAP

[Releases](https://github.com/Torry2022/turbo-ai-chat-harmonyos/releases) provide signed HAPs. Install via hdc:

```sh
hdc install -r turbo-ai-chat-harmonyos-vX.Y.Z-signed.hap
```

You can also use [Xiaobai Debug Assistant](https://github.com/likuai2010/auto-installer) for graphical installation. The signed HAP only works on devices within the current debug signing profile. For other devices, download the unsigned HAP and re-sign with your own developer account.

## Fallback: Manual Model Push

In-app download and zip import are the recommended approaches. Manual `hdc` push is kept as a debugging fallback.

The model directory must be in **MNN format** — exported via MNN `llmexport.py` from HuggingFace weights, containing `config.json`, `llm_config.json`, tokenizer file, `llm.mnn`, `llm.mnn.weight`, etc. Original HuggingFace safetensors, GGUF, and MLX weights cannot be used directly.

### Pushing built-in model directories

Use the following commands to restore built-in model directories when in-app download is unavailable:

```sh
cd models
hdc file send -b com.example.gemma4mnn gemma-4-E2B-it-MNN /data/storage/el2/base/haps/entry/files/
hdc file send -b com.example.gemma4mnn MiniCPM5-1B-MNN /data/storage/el2/base/haps/entry/files/
hdc file send -b com.example.gemma4mnn Qwen3-4B-Instruct-2507-MNN /data/storage/el2/base/haps/entry/files/
```

> The `-b` flag specifies the bundle name and is required to write into the app sandbox. Zip files larger than ~2 GB may fail due to system ZIP compatibility — use `file send` to push the directory directly instead.

### Registering a pushed model as an import

To register a pushed model as an imported model:

1. Prepare a complete MNN model directory. It should contain `config.json`, `llm_config.json`, `llm.mnn`, `llm.mnn.weight`, tokenizer files, and related metadata.
2. Put the directory under the repository `models/` directory, for example `models/Qwen3-4B-Instruct-2507-MNN`.
3. Run `hdc file send` from the parent directory of the model directory:

   ```sh
   cd models
   hdc file send -b com.example.gemma4mnn Qwen3-4B-Instruct-2507-MNN /data/storage/el2/base/haps/entry/files/model-imports/
   ```

4. Verify the directory on the device:

   ```sh
   hdc shell "ls -la /data/app/el2/100/base/com.example.gemma4mnn/haps/entry/files/model-imports/Qwen3-4B-Instruct-2507-MNN"
   ```

   The directory should contain `config.json`, `llm_config.json`, `llm.mnn`, `llm.mnn.weight`, and tokenizer files.

5. Open the app → Model tab → expand "Model Management".
6. Tap "Scan pushed directory". The app will find `config.json`, `.mnn` files, and a compatible chat template, then update `model-imports/imported-models.json` automatically.
7. Select the new imported model from the model list and load it.

The scanner only checks first-level subdirectories under `model-imports/`. Directory names must not contain `/`, `\`, or `..`. On Windows, run `hdc file send` from the parent directory of the model directory to avoid preserving extra parent paths or writing backslashes into the app sandbox. If your model is not under the repository `models/` directory, `cd` to that model directory's parent before pushing.

Imported models are formatted by MNN by default. If `llm_config.json` contains `jinja.chat_template`, the app uses it directly. If that field is missing, the app only provides extra compatibility for automatically recognized legacy ChatML templates; otherwise, the directory is skipped as incompatible.

## PC-side Model Download Scripts

```sh
# Qwen3-4B-Instruct (~2.5 GB)
./scripts/download_qwen3_4b_mnn.sh

# Gemma-4-E2B-it (~3.7 GB)
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

The app uses **MNN model directory** format. Built-in models are downloaded from ModelScope: Qwen3-4B-Instruct and Gemma-4-E2B-it from the [MNN organization](https://modelscope.cn/organization/MNN), MiniCPM5-1B BF16 from [TorryJi](https://modelscope.cn/models/TorryJi/MiniCPM5-1B-MNN-BF16). Original HuggingFace weights must be converted via MNN `llmexport.py` before use.

## Native API

ArkTS calls N-API via `import entry from 'libentry.so'`:

```ts
entry.loadModelAsync(configPath, threadNum, maxNewTokens, settings): Promise<string>
entry.generateRawPromptStream(prompt, maxNewTokens, endWith, settings, onChunk): Promise<GenerationResult>
entry.generateChatStream(messages, maxNewTokens, settings, onChunk): Promise<GenerationResult>
entry.stopGeneration(): void
entry.reset(): void
entry.isLoaded(): boolean
```

## License

Apache-2.0. MNN and model files follow their respective upstream licenses. This repository does not commit model weights.
