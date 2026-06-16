# Turbo AI Chat

[中文](README.md) | English

![Turbo AI Chat hero](docs/images/hero.png)

**Turbo AI Chat** is a HarmonyOS NEXT native local LLM chat demo. The app uses ArkTS for the UI, calls a C++ inference layer through N-API, and runs MNN models such as **Gemma 4 E2B** and **MiniCPM5-1B** locally on a HarmonyOS device with the MNN Runtime.

Keywords: HarmonyOS NEXT, HarmonyOS native LLM, ArkTS, N-API, MNN, Gemma 4, MiniCPM5, on-device AI, local LLM, mobile inference, ModelScope model.

## Background

This project started from a simple question: **Can HarmonyOS NEXT run a local large language model inside a native app?**

The early direction was to look for GGUF / llama.cpp examples on HarmonyOS. In practice, the MNN route was more stable for a native HarmonyOS project: MNN has mature mobile inference support, and Gemma 4 already has an MNN-exported model. This repository narrows the first milestone down to one thing:

> Load a local Gemma 4 model on a real HarmonyOS NEXT device and provide an interactive streaming chat UI.

This is not a cloud-chat wrapper and not a WebView shell. Model files live on the device, and inference runs inside the app's native layer.

## Quick Start: Clone, Run, Install Built-in Models

The recommended flow is: **build and install the app from source, then let the app download the built-in model files**. New users no longer need to download model directories on a PC first and push them into the app sandbox with `hdc file send`.

### 1. Clone the repository

```sh
git clone https://github.com/Torry2022/turbo-ai-chat-harmonyos.git
cd turbo-ai-chat-harmonyos
```

You can also start from the upstream repository:

```sh
git clone https://github.com/Turbo1123/turbo-ai-chat-harmonyos.git
cd turbo-ai-chat-harmonyos
```

### 2. Open with DevEco Studio and configure signing

1. Open the project root in DevEco Studio.
2. Log in to your Huawei developer account.
3. Go to `File > Project Structure > Signing Configs`.
4. Enable automatic signing for the default product.
5. Make sure your physical device has Developer options and USB debugging enabled.

`build-profile.json5` keeps only the default product's `signingConfig` binding. Real certificates, profiles, private key paths, and passwords should not be committed to the repository.

### 3. Build and install on a physical device

You can run the project directly from DevEco Studio, or use the command line:

```sh
hvigor assembleHap --no-daemon
hdc list targets
hdc install -r entry/build/default/outputs/default/entry-default-signed.hap
```

If `hvigor` is not available globally, run it through the project dependency:

```sh
node ./node_modules/@ohos/hvigor/bin/hvigor.js assembleHap --no-daemon
```

### 4. Install built-in models in the app

The repository and the HAP do **not** include model weights. After installing the app:

1. Open the Model tab.
2. Select `Gemma 4 E2B` or `MiniCPM5-1B`.
3. Tap "Load model".
4. If the selected built-in model directory is missing or incomplete, the app opens the "Install built-in model" dialog.
5. Tap "Download and install" and keep the app in the foreground.
6. After download completion, the app continues loading the model. Go back to the Chat tab and start chatting.

Built-in models are downloaded into the app sandbox:

```text
/data/storage/el2/base/haps/entry/files/gemma-4-E2B-it-MNN/
/data/storage/el2/base/haps/entry/files/MiniCPM5-1B-MNN/
```

Approximate model sizes: Gemma 4 E2B `3.7 GB`, MiniCPM5-1B `625 MB`. Make sure the device has enough storage and a stable network connection.

## Features

- Native HarmonyOS NEXT ArkTS UI
- C++ / N-API inference bridge
- On-device inference with MNN LLM Runtime
- Gemma 4 / MiniCPM5 MNN model switching and loading
- Streaming generation
- Multi-turn conversation context
- Image picker entry
- CPU / memory status panel
- Startup built-in model check with one-click download guidance
- Chinese UI, immersive layout, bottom tabs

## Screenshots

| Chat | Header | Input |
| --- | --- | --- |
| ![chat main](docs/images/chat-main.jpeg) | ![chat header](docs/images/chat-header.jpeg) | ![chat input](docs/images/chat-input.jpeg) |

## Model Format

The current mainline uses an **MNN model directory**, not direct `.gguf` loading.

Built-in selectable models:

| Model | Default directory | Input support |
| --- | --- | --- |
| Gemma 4 E2B | `gemma-4-E2B-it-MNN/` | Text, image |
| MiniCPM5-1B | `MiniCPM5-1B-MNN/` | Text |

The app reads `config.json` from the selected model directory. Switching models only changes the selected item; the previous model is released and the new model is loaded only after tapping "Load model". Chat templates are delegated to MNN through each model's `llm_config.json` by default, instead of being hard-coded by the app.

Recommended built-in model sources:

- ModelScope: [`MNN/gemma-4-E2B-it-MNN`](https://modelscope.cn/models/MNN/gemma-4-E2B-it-MNN)
- ModelScope: [`MNN/MiniCPM5-1B-MNN`](https://modelscope.cn/models/MNN/MiniCPM5-1B-MNN)
- Model type: Gemma 4 E2B instruction, MNN 4-bit quantized export
- Entry file: `config.json`

The model directory should include:

```text
gemma-4-E2B-it-MNN/
  config.json
  llm_config.json
  tokenizer.mtok
  llm.mnn
  llm.mnn.weight
  ple_embeddings_int4.bin
  visual.mnn
  visual.mnn.weight
  audio.mnn
  audio.mnn.weight
```

MiniCPM5-1B must include:

```text
MiniCPM5-1B-MNN/
  config.json
  llm_config.json
  tokenizer.mtok
  llm.mnn
  llm.mnn.weight
  embeddings_int4.bin
```

The official BF16, GGUF, and MLX weights cannot be loaded directly by the current native MNN inference layer.

If you have a GGUF model, you need a conversion path or a separate llama.cpp HarmonyOS port. This repository does not directly read GGUF yet.

## Download HAP

Installable HAP builds are attached to GitHub Releases:

- [Latest Release](https://github.com/Turbo1123/turbo-ai-chat-harmonyos/releases/latest)

Install example:

```sh
hdc install -r turbo-ai-chat-harmonyos-v0.1.0-signed.hap
```

The HAP does not bundle model weights. Gemma 4 E2B is about 3.7 GB, and MiniCPM5-1B is about 625 MB. After installing the app, if a built-in model directory is missing, the app prompts you to download and install it from ModelScope into the app sandbox.

Note: the Release HAP is debug-signed. If your device is not covered by the debug profile, installation may fail. In that case, open the project from source and rebuild it with DevEco Studio automatic signing using your own Huawei developer account.

## Fallback: Download Models On PC

Normally, install the app and follow the in-app prompt to download built-in models. The PC-side workflow below is kept for debugging, offline preparation, or restricted network environments.

```sh
./scripts/download_gemma4_e2b_mnn.sh
```

Default output:

```text
models/gemma-4-E2B-it-MNN/
```

You can also choose a custom directory:

```sh
./scripts/download_gemma4_e2b_mnn.sh /path/to/gemma-4-E2B-it-MNN
```

MiniCPM5-1B is best downloaded in the app from ModelScope. You can also prepare an MNN directory manually, for example:

```text
models/MiniCPM5-1B-MNN/
```

The script downloads Gemma 4 E2B from ModelScope by default. If the `modelscope` CLI is not available, it falls back to the Python `modelscope` package. Install it first if needed:

```sh
python3 -m pip install modelscope
```

## Fallback: Push Models Manually

The app reads the sandbox paths below by default. Normally the in-app downloader writes these directories automatically; the `hdc` workflow is kept as a debugging fallback.

```text
/data/storage/el2/base/haps/entry/files/gemma-4-E2B-it-MNN/config.json
/data/storage/el2/base/haps/entry/files/MiniCPM5-1B-MNN/config.json
```

That is the sandbox path visible to the app. When using `hdc file send`, you usually need to push to the physical path:

```text
/data/app/el2/100/base/com.example.gemma4mnn/haps/entry/files/gemma-4-E2B-it-MNN/
```

Recommended script:

```sh
./scripts/push_model_to_device.sh
./scripts/push_model_to_device.sh models/MiniCPM5-1B-MNN
```

If your device user id is not `100`, specify it explicitly:

```sh
USER_ID=100 ./scripts/push_model_to_device.sh
```

Specify a device target:

```sh
HDC_TARGET=<device-id> ./scripts/push_model_to_device.sh
```

Manual push example:

```sh
hdc shell "mkdir -p /data/app/el2/100/base/com.example.gemma4mnn/haps/entry/files"
hdc file send -b com.example.gemma4mnn models/gemma-4-E2B-it-MNN /data/storage/el2/base/haps/entry/files/
```

## Build From Source Details

Requirements:

- DevEco Studio / HarmonyOS SDK
- HarmonyOS NEXT physical device
- Developer options and USB debugging enabled
- Huawei developer account for automatic signing
- `hdc` and `hvigor` available in `PATH`

Build HAP:

```sh
hvigor assembleHap --no-daemon
```

Install:

```sh
hdc list targets
hdc install -r entry/build/default/outputs/default/entry-default-signed.hap
```

If signing is not configured on your machine:

1. Log in to your Huawei developer account in DevEco Studio.
2. Open this project.
3. Go to `File > Project Structure > Signing Configs`.
4. Enable automatic signing for the default product.
5. Build again.

Real signing material, certificate paths, and passwords are intentionally not committed to `build-profile.json5`.

## MNN Runtime

This repository includes the HarmonyOS arm64 `libMNN.so` and the minimal MNN headers used by the demo, so the project can build directly.

To rebuild MNN from source:

```sh
git clone https://github.com/alibaba/MNN.git ../MNN
./scripts/build_mnn_ohos.sh
./scripts/stage_mnn_ohos.sh
```

`stage_mnn_ohos.sh` stages outputs into:

```text
entry/src/main/libs/arm64-v8a/libMNN.so
third_party/mnn/include/
```

## Native API

ArkTS imports the native module:

```ts
import entry from 'libentry.so';
```

N-API surface:

```ts
entry.loadModelAsync(configPath, threadNum, maxNewTokens): Promise<string>
entry.generateChatStream(messages, maxNewTokens, onChunk): Promise<string>
entry.reset(): void
entry.isLoaded(): boolean
```

## Roadmap
- Gemma 4 multimodal image input
- More detailed token / first-token latency / tokens-per-second metrics
- Release build pipeline
- GGUF / llama.cpp route comparison and experiment branch

## License

Apache-2.0. MNN and model files follow their respective upstream licenses. This repository does not commit model weights.
