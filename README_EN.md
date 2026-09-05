# Turbo AI Chat

[中文](README.md) | English

![License](https://img.shields.io/badge/license-Apache--2.0-blue)
![HarmonyOS](https://img.shields.io/badge/HarmonyOS-NEXT-orange)
![Runtime](https://img.shields.io/badge/runtime-MNN%20CPU-green)

![Turbo AI Chat hero](docs/images/hero.png)

**Turbo AI Chat is a HarmonyOS NEXT native on-device LLM chat application** for validating a complete local-inference pipeline on HarmonyOS devices. It is built with ArkTS, C++ N-API, and MNN Runtime, ships profiles for Qwen3-4B-Instruct, MiniCPM5-1B, and Gemma-4-E2B-it, and can add compatible text and multimodal MNN models through the Model Gallery or local import. The app also includes streaming chat, model switching, image understanding, runtime monitoring, and an OpenAI-compatible LAN API.

## Table of Contents

- [Project Origin and Evolution](#project-origin-and-evolution)
- [Background](#background)
- [Recent Highlights](#recent-highlights)
- [System Requirements](#system-requirements)
- [Quick Start](#quick-start)
- [Features](#features)
- [Screenshots](#screenshots)
- [OpenAI-Compatible API Server](#openai-compatible-api-server)
- [Model Management](#model-management)
- [Model Format](#model-format)
- [Inference Backend and Performance](#inference-backend-and-performance)
- [Architecture](#architecture)
- [Native API](#native-api)
- [License](#license)

## Project Origin and Evolution

This project started from [Turbo1123/turbo-ai-chat-harmonyos](https://github.com/Turbo1123/turbo-ai-chat-harmonyos). The upstream repository's first two commits established an on-device ArkTS → N-API → C++ → MNN inference pipeline with Gemma 4 text generation, streaming output, and multi-turn conversation, providing a working foundation for subsequent development.

While retaining that foundation, this repository gradually expanded the Gemma 4-oriented implementation into a general inference path for compatible MNN model directories. It completed the image-input path from ArkTS to MNN and added generation control, stop reasons, token statistics, model-directory validation, and lifecycle management. At the application layer, subsequent work added model switching and import, the online Model Gallery, offline voice input, runtime monitoring, an OpenAI-compatible LAN API, and repeated regression testing on physical devices.

The repository has since left the original fork network and is now maintained independently, while preserving the upstream commit history, Apache-2.0 license, and source attribution. See [Core Inference Pipeline Evolution](docs/architecture/core-inference-evolution.md) for the upstream baseline, implementation changes, and corresponding commits, and [`MODIFICATIONS.md`](MODIFICATIONS.md) for file-level modification notices. The complete code difference is available at [`f946a84...main`](https://github.com/Torry2022/turbo-ai-chat-harmonyos/compare/f946a842...main).

## Background

In the HarmonyOS ecosystem, on-device AI inference today largely depends on Android compatibility layers running Android apps. Turbo AI Chat validates a different path with a fully native pipeline (ArkTS → N-API → MNN → CPU):

- **Native architecture**: inference directly via HarmonyOS NDK, no Android compatibility layer overhead
- **Reproducible out of the box**: preset models downloaded from ModelScope through the Model Gallery, no HuggingFace required (China-network friendly)
- **Reusable engineering**: MNN Runtime wrapper, streaming pipeline, Markdown rendering as integration references for other HarmonyOS AI apps
- **Developer-friendly**: one hdc command to inspect raw inference logs (`raw_output_debug.txt`) containing prompt, model output, sampling parameters, and token statistics

  ```sh
  hdc shell "cat /data/app/el2/100/base/com.example.gemma4mnn/haps/entry/files/raw_output_debug.txt"
  ```

## Recent Highlights

**Tablet and PC support**

- Navigation switches between bottom tabs, a compact sidebar, and a full sidebar according to actual window width. Model and monitoring pages use columns in wide windows.
- Physical keyboards support Enter to send, Shift+Enter for a line break, Ctrl+N for a new conversation, and Esc to leave input or close dismissible dialogs. Input-method candidate selection takes priority.
- Updated launch backgrounds, system safe areas, dialog sizing, chat reading width, and runtime-strip placement, with mouse dragging for model reordering.

**Models and market**

- Switched the default text model to Qwen3-4B-Instruct, with in-app model-market installation from ModelScope for preset models and additional MNN model entries.
- The Model Gallery supports online catalog refresh with a local fallback cache. Updating [`model-catalog/catalog.json`](model-catalog/catalog.json) publishes compatible model entries without requiring a new app package.
- Forks and derivative builds still read this repository's online catalog by default. To maintain an independent Model Gallery, change `REMOTE_MODEL_CATALOG_URL` in [`ModelCatalogService.ets`](entry/src/main/ets/services/ModelCatalogService.ets) to your own Raw catalog URL and rebuild the app.
- Model-market downloads support stop-and-resume behavior. Closing a stopped install dialog clears unfinished temporary download files to avoid sandbox leftovers.
- In addition to zip import, you can push a complete MNN model directory into the app sandbox and scan it from the Model tab to avoid large zip import failures.
- The Model tab supports model ordering and deleting installed model directories, and disables related controls during generation, loading, or import to avoid inconsistent state.

**Chat experience**

- Streaming output can be interrupted; stopped responses are not added to future conversation context.
- Added offline Mandarin voice input: an empty, unfocused composer shows a microphone, partial transcripts appear in real time with voice-activity feedback, and the final text remains editable before sending.
- Markdown and thinking-block parsing results are cached, UTF-8 streaming chunks and table column stability are improved, completed generations no longer pull the view back to the bottom while the user is reading history, and the chat list scrollbar is hidden.
- The Chat tab includes a compact device status strip for app CPU, app memory, and device temperature, with threshold-based value colors.

**Stability and diagnostics**

- Upgraded MNN Runtime to 3.6.0 and synchronized the HarmonyOS `arm64-v8a` shared library and public headers.
- Model loading, market installation, and local import share one directory preflight that validates configuration, referenced weights, visual files, and chat-template compatibility before native inference starts.
- Image inference preserves the visual input size declared by each model directory, supporting MNN multimodal models with different visual-grid configurations.
- A real-device `ohosTest` regression baseline now covers context handling, Markdown, thinking blocks, model compatibility rules, imported-model naming, and download progress.
- The Monitor tab includes app storage usage, model state, version/license text, and tighter device metrics.
- Model load failures keep the error in the load dialog and reset inference state, making low-memory or failed-load recovery clearer.
- Markdown tables, lists, code snippets, thinking blocks, raw output logs, and MNN chat-template handling were improved for diagnosing repetition, stop tokens, and prompt template issues.

**API server**

- The currently loaded MNN model can be exposed as an OpenAI-compatible LAN service for clients such as Cherry Studio.
- `/v1/models`, `/v1/chat/completions`, and `/v1/responses` are supported, including SSE streaming and optional Bearer authentication.

## System Requirements

| Item | Recommended |
|------|-------------|
| System | HarmonyOS NEXT. The project currently uses `compatibleSdkVersion` `6.1.0(23)` and `targetSdkVersion` `6.1.1(24)` |
| Device | ARM64 HarmonyOS phone, tablet, or PC (`phone` / `tablet` / `2in1`). The emulator is not the target environment for local MNN inference in this project |
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

The app and HAP do not include model weights. Open the app → Model tab → Model Gallery, or select Qwen3-4B-Instruct, MiniCPM5-1B, or Gemma-4-E2B-it and tap load. The app will guide you to download from ModelScope into the app sandbox.

| Model | Size | Capability |
|------|------|------|
| Qwen3-4B-Instruct | ~2.5 GB | Text |
| Gemma-4-E2B-it | ~3.7 GB | Text + Image |
| MiniCPM5-1B (BF16) | ~2.1 GB | Text |

### 3. Start chatting

After the model loads, return to the Chat tab and send a message. MiniCPM5-1B displays thinking blocks (`<think>`). Gemma-4-E2B-it supports image input.

With a physical keyboard, Enter sends from the chat input and Shift+Enter inserts a line break; the input method handles candidate selection first. Ctrl+N starts a new conversation. Esc leaves the input or closes a dismissible dialog without exiting the app. With the on-screen keyboard, use the send button. Chat content is centered with a maximum width in wide windows; opening the on-screen keyboard reduces the content area while keeping the header and input visible.

## Features

- Adaptive navigation: bottom tabs in narrow windows and a sidebar in wider windows. Resizing retains page instances; monitoring pauses when hidden and preserves its scroll position.
- The chat runtime strip spans only the page content area and does not shift the sidebar. Wide-screen chat uses the same maximum page width as other tabs, with separate message-width limits for readability.
- Wide model pages place the model list beside its settings. Long-press a handle to reorder by touch, or drag it directly with a mouse. Resizing cancels an active drag without applying its tentative order.
- Monitoring cards switch between one and two columns according to available width, with metrics sharing the space inside each card.
- Dialogs fit the available window width and allow long body text to scroll. The Model Gallery shrinks when the on-screen keyboard opens, and keyboard focus stays out of the underlying page while a dialog is open.
- Local inference: models run on-device, no network required
- Streaming output: updates responses from native inference callback chunks in real time
- Stop generation: interrupt the current response while it is streaming
- Voice input: offline Mandarin recognition through Core Speech Kit, with live partial results and manual stop
- Model switching: switch between preset models, installed market models, and imported models
- Thinking blocks: MiniCPM5-1B displays reasoning process
- Markdown rendering: code blocks (with copy button), tables, blockquotes, links, etc., with compatibility handling for incomplete inline code, empty table cells, and table column jitter during streaming output
- Long-conversation scrolling optimization: caches Markdown / thinking-block parsing and pauses auto-follow while the user is scrolling
- Generation parameter controls: temperature, Top-P/K, penalty terms, etc.
- Performance metrics: TTFT, TPOT, tokens/s per assistant message
- Model management: model-market download, model ordering, and deleting installed model directories
- Import local MNN models via zip, or by pushing a directory and scanning it in the app; standard MNN export directories use `jinja.chat_template` from `llm_config.json`
- OpenAI-compatible API: serve the currently loaded model to Cherry Studio and other LAN clients with streaming output and Bearer authentication

## Screenshots

| Chat | Model | Monitor |
| --- | --- | --- |
| ![chat](docs/images/chat.jpg) | ![models](docs/images/models.jpg) | ![monitor](docs/images/monitor.jpg) |

Tablet in landscape:

![Tablet model page](docs/images/tablet-models.jpg)

Maximized PC window:

![PC model page](docs/images/pc-models.jpg)

## OpenAI-Compatible API Server

After loading a model, open the **Service** tab, choose a port and optionally enable the app-generated API key, then start the server. The page displays a LAN address such as `http://192.168.1.126:8080`. If no model is loaded, starting the server opens the model-loading flow and continues automatically after a successful load. Releasing, switching, or deleting the current model stops a running server automatically.

When adding an OpenAI-compatible provider in Cherry Studio, enter the displayed base URL without appending an endpoint. If API-key authentication is enabled, enter the same key, then fetch the model list. The server provides:

- `GET /v1/models`
- `POST /v1/chat/completions`
- `POST /v1/responses`

The Service tab shows operational logs for server lifecycle, request paths, model parameters, response status, latency, and output size. It does not log API keys, prompts, or response text.

Wide windows place service settings beside the API logs. Narrowing the window restores a single column without restarting an active server.

The first version accepts text input only, serves the currently loaded model, and processes one generation request at a time. For models that emit `<think>`, `/v1/chat/completions` returns reasoning in `reasoning_content`, while `/v1/responses` returns a separate reasoning output item; the final answer remains in the regular text field. For now, `usage` accurately reports only the total generated-token count; exact input and reasoning breakdowns are not available. The server runs with the app and stops when the app exits; the device and client must be reachable on the same LAN.

## Install from HAP

[Releases](https://github.com/Torry2022/turbo-ai-chat-harmonyos/releases) provide signed HAPs (only for devices included in the current profile). Install via hdc:

```sh
hdc install -r turbo-ai-chat-harmonyos-vX.Y.Z-signed.hap
```

You can also sideload the HAP with [Xiaobai Debug Assistant](https://github.com/likuai2010/auto-installer). Debug-signed packages only work on devices included in the current profile; for other devices, download the unsigned HAP and re-sign it with your own developer account.

## Model Management

The recommended path is to install models from the in-app Model Gallery. Use zip import or manual directory push for large models, local conversion testing, or debugging.

- **Model Gallery**: refresh the online catalog and install preset or extended models from ModelScope; if refresh fails, the app keeps the last valid cache or its bundled catalog.
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

For both zip import and directory scanning, the app reads `is_visual` from `llm_config.json` to detect image capability automatically. Generated short names retain parameter sizes such as `0.6B` and `1.8B` whenever possible.

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

On-device LLM decoding includes token-by-token serial stages, and actual throughput can also be limited by memory bandwidth, cache contention, and system thermal control. In assistant messages, TTFT is the end-to-end time from request submission to the first complete UTF-8 output chunk. TPOT and tokens/s cover only the decode phase from the first output to completion and use the native generated-token count. Evaluate these metrics together with app CPU, app memory, and device temperature.

## Architecture

```text
ChatTab / ModelTab / MonitorTab / ...
                |
          ChatViewModel
      |-- GenerationWorkflow -- ImagePayloadService
      |-- ModelLifecycleService -- preflight / install / import / scan
      `-- NativeInferenceService (shared by both workflows)
                |
        N-API Bridge (libentry.so)
                |
     MnnLlmRunner (mnn_llm_runner.cpp)
        |          |           |
      text      raw prompt     image
                |
       MNN Runtime (libMNN.so)
                |
           CPU Backend
```

`MnnLlmRunner` provides native inference for compatible MNN `Transformer::Llm` directories. ArkTS lifecycle services handle installation, import, and directory preflight, while text, raw-prompt, and image generation share a stable N-API boundary. See [Core Inference Pipeline Evolution](docs/architecture/core-inference-evolution.md) for details.

## Native API

ArkTS calls N-API via `import entry from 'libentry.so'`:

```ts
entry.loadModelAsync(configPath, threadNum, maxNewTokens, settings): Promise<string>
entry.generateRawPromptStream(prompt, maxNewTokens, endWith, settings, onChunk): Promise<GenerationResult>
entry.generateChatStream(messages, maxNewTokens, settings, onChunk): Promise<GenerationResult>
entry.generateImageChatStream(messages, pixels, width, height, maxNewTokens, settings, onChunk): Promise<GenerationResult>
entry.stopGeneration(): void
entry.reset(): void
entry.isLoaded(): boolean
```

## License

This repository's source code is licensed under Apache-2.0.

MNN Runtime and model weights follow their respective upstream licenses or model-card terms. This repository and Release HAPs do not include model weights. Users who download models through the Model Gallery, scripts, or manual push should follow the terms of the corresponding upstream source.

- [MNN](https://github.com/alibaba/MNN)
- [Qwen3-4B-Instruct-2507-MNN](https://modelscope.cn/models/MNN/Qwen3-4B-Instruct-2507-MNN)
- [Gemma-4-E2B-it-MNN](https://modelscope.cn/models/MNN/Gemma-4-E2B-it-MNN)
- [MiniCPM5-1B-MNN-BF16](https://modelscope.cn/models/TorryJi/MiniCPM5-1B-MNN-BF16)
