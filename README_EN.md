# Turbo AI Chat

[中文](README.md) | English

![License](https://img.shields.io/badge/license-Apache--2.0-blue)
![HarmonyOS](https://img.shields.io/badge/HarmonyOS-NEXT-orange)
![Runtime](https://img.shields.io/badge/runtime-MNN%20CPU-green)

![Turbo AI Chat hero](docs/images/hero.png)

**Turbo AI Chat is a HarmonyOS NEXT native on-device LLM chat application** for validating a complete local-inference pipeline on HarmonyOS devices. It is built with ArkTS, C++ N-API, and MNN Runtime, ships profiles for Qwen3-4B-Instruct, MiniCPM5-1B, and Gemma-4-E2B-it, and can add compatible text and multimodal MNN models through the model market or local import. The app also includes streaming chat, model switching, image understanding, and runtime monitoring.

This repository is forked from [Turbo1123/turbo-ai-chat-harmonyos](https://github.com/Turbo1123/turbo-ai-chat-harmonyos).

## Table of Contents

- [Background](#background)
- [Recent Highlights](#recent-highlights)
- [System Requirements](#system-requirements)
- [Quick Start](#quick-start)
- [Features](#features)
- [Screenshots](#screenshots)
- [Model Management](#model-management)
- [Model Format](#model-format)
- [Inference Backend and Performance](#inference-backend-and-performance)
- [Architecture](#architecture)
- [Native API](#native-api)
- [License](#license)

## Background

In the HarmonyOS ecosystem, on-device AI inference today largely depends on Android compatibility layers running Android apps. Turbo AI Chat validates a different path with a fully native pipeline (ArkTS → N-API → MNN → CPU):

- **Native architecture**: inference directly via HarmonyOS NDK, no Android compatibility layer overhead
- **Reproducible out of the box**: preset models downloaded from ModelScope through the model market, no HuggingFace required (China-network friendly)
- **Reusable engineering**: MNN Runtime wrapper, streaming pipeline, Markdown rendering as integration references for other HarmonyOS AI apps
- **Developer-friendly**: one hdc command to inspect raw inference logs (`raw_output_debug.txt`) containing prompt, model output, sampling parameters, and token statistics

  ```sh
  hdc shell "cat /data/app/el2/100/base/com.example.gemma4mnn/haps/entry/files/raw_output_debug.txt"
  ```

## Recent Highlights

**Models and market**

- Switched the default text model to Qwen3-4B-Instruct, with in-app model-market installation from ModelScope for preset models and additional MNN model entries.
- Model-market downloads support stop-and-resume behavior. Closing a stopped install dialog clears unfinished temporary download files to avoid sandbox leftovers.
- In addition to zip import, you can push a complete MNN model directory into the app sandbox and scan it from the Model tab to avoid large zip import failures.
- The Model tab supports model ordering and deleting installed model directories, and disables related controls during generation, loading, or import to avoid inconsistent state.

**Chat experience**

- Streaming output can be interrupted; stopped responses are not added to future conversation context.
- Markdown and thinking-block parsing results are cached, UTF-8 streaming chunks and table column stability are improved, completed generations no longer pull the view back to the bottom while the user is reading history, and the chat list scrollbar is hidden.
- The Chat tab includes a compact device status strip for app CPU, app memory, and device temperature, with threshold-based value colors.

**Stability and diagnostics**

- Model loading, market installation, and local import share one directory preflight that validates configuration, referenced weights, visual files, and chat-template compatibility before native inference starts.
- Image inference preserves the visual input size declared by each model directory, supporting MNN multimodal models with different visual-grid configurations.
- A real-device `ohosTest` regression baseline now covers context handling, Markdown, thinking blocks, model compatibility rules, imported-model naming, and download progress.
- The Monitor tab includes app storage usage, model state, version/license text, and tighter device metrics.
- Model load failures keep the error in the load dialog and reset inference state, making low-memory or failed-load recovery clearer.
- Markdown tables, lists, code snippets, thinking blocks, raw output logs, and MNN chat-template handling were improved for diagnosing repetition, stop tokens, and prompt template issues.

## System Requirements

| Item | Recommended |
|------|-------------|
| System | HarmonyOS NEXT. The project currently uses `compatibleSdkVersion` `6.1.0(23)` and `targetSdkVersion` `6.1.1(24)` |
| Device | Real device. The emulator is not the target environment for local MNN inference in this project |
| RAM | 8 GB or more is recommended for Qwen3-4B-Instruct / Gemma-4-E2B-it. MiniCPM5-1B is better suited for lower-memory validation |
| Storage | The HAP is small; model weights dominate storage. A single MNN model directory usually requires several GB |
| Network | In-app model-market installation downloads from ModelScope, so first-time model installation requires ModelScope access |

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

### 2. Install models

The app and HAP do not include model weights. Open the app → Model tab → Model Market, or select Qwen3-4B-Instruct, MiniCPM5-1B, or Gemma-4-E2B-it and tap load. The app will guide you to download from ModelScope into the app sandbox.

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
- Model switching: switch between preset models, installed market models, and imported models
- Thinking blocks: MiniCPM5-1B displays reasoning process
- Markdown rendering: code blocks (with copy button), tables, blockquotes, links, etc., with compatibility handling for incomplete inline code, empty table cells, and table column jitter during streaming output
- Long-conversation scrolling optimization: caches Markdown / thinking-block parsing and pauses auto-follow while the user is scrolling
- Generation parameter controls: temperature, Top-P/K, penalty terms, etc.
- Performance metrics: TTFT, TPOT, tokens/s per assistant message
- Model management: model-market download, model ordering, and deleting installed model directories
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

## Model Management

The recommended path is to install models from the in-app model market. Use zip import or manual directory push for large models, local conversion testing, or debugging.

- **Model market**: download and install preset or extended models from ModelScope on the Model tab.
- **Zip import**: useful for small or medium complete MNN model directories.
- **Manual directory push**: useful for large models, offline debugging, or when zip import fails; push the directory and scan it from the Model tab.

### Fallback: Manual Model Push

Model-market download and in-app zip import are the recommended approaches. Manual `hdc` push is kept as a debugging fallback.

The model directory must be in **MNN format** — exported via MNN `llmexport.py` from HuggingFace weights, containing `config.json`, `llm_config.json`, tokenizer file, `llm.mnn`, `llm.mnn.weight`, etc. Original HuggingFace safetensors, GGUF, and MLX weights cannot be used directly.

#### Pushing built-in model directories

Use the following commands to restore built-in model directories when in-app download is unavailable:

```sh
cd models
hdc file send -b com.example.gemma4mnn gemma-4-E2B-it-MNN /data/storage/el2/base/haps/entry/files/
hdc file send -b com.example.gemma4mnn MiniCPM5-1B-MNN /data/storage/el2/base/haps/entry/files/
hdc file send -b com.example.gemma4mnn Qwen3-4B-Instruct-2507-MNN /data/storage/el2/base/haps/entry/files/
```

> The `-b` flag specifies the bundle name and is required to write into the app sandbox.

#### Registering a pushed model as an import

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

The app checks MNN chat templates consistently across model-market downloads, preset model installation, and imported model scanning. If `llm_config.json` contains `jinja.chat_template`, the app uses it directly. If that field is missing, the app only provides extra compatibility for automatically recognized legacy ChatML templates; otherwise, the directory is skipped as incompatible.

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

## Inference Backend and Performance

The current version runs local inference with the **MNN CPU backend**. GPU / NPU backends are not integrated yet. The "inference threads" setting on the Model tab is passed to the native layer as the MNN CPU thread count, with a default value of 6.

On-device LLM decoding includes token-by-token serial stages, and actual throughput can also be limited by memory bandwidth, cache contention, and system thermal control. For performance evaluation, prefer the TTFT, ms/tok, and tokens/s metrics shown at the bottom of assistant messages, together with app CPU, app memory, and device temperature.

## Architecture

```text
ArkTS UI Layer
ChatTab / ModelTab / MonitorTab / ...
        |
NativeInferenceService (ArkTS)
        |
N-API Bridge (libentry.so)
        |
GemmaRunner (gemma_runner.cpp)
        |
MNN Runtime (libMNN.so)
        |
CPU Backend
```

The `GemmaRunner` name is kept from the early Gemma prototype. The current native wrapper is used for Qwen, MiniCPM, Gemma, and other compatible MNN LLM directories.

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

This repository's source code is licensed under Apache-2.0.

MNN Runtime and model weights follow their respective upstream licenses or model-card terms. This repository and Release HAPs do not include model weights. Users who download models through the model market, scripts, or manual push should follow the terms of the corresponding upstream source.

- [MNN](https://github.com/alibaba/MNN)
- [Qwen3-4B-Instruct-2507-MNN](https://modelscope.cn/models/MNN/Qwen3-4B-Instruct-2507-MNN)
- [Gemma-4-E2B-it-MNN](https://modelscope.cn/models/MNN/Gemma-4-E2B-it-MNN)
- [MiniCPM5-1B-MNN-BF16](https://modelscope.cn/models/TorryJi/MiniCPM5-1B-MNN-BF16)
