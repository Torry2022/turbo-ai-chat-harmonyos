# Turbo AI Chat

[English](README_EN.md) | 中文

![Turbo AI Chat hero](docs/images/hero.png)

**Turbo AI Chat** 是一个 HarmonyOS NEXT 原生本地大模型聊天 Demo。它用 ArkTS 构建界面，通过 N-API 调用 C++ 原生推理层，并使用 MNN Runtime 在鸿蒙设备端加载 **Gemma 4 E2B**、**MiniCPM5-1B** 等 MNN 模型完成离线对话。

关键词：HarmonyOS NEXT, HarmonyOS native LLM, ArkTS, N-API, MNN, Gemma 4, MiniCPM5, on-device AI, local LLM, mobile inference, ModelScope model.

## 项目背景

这个项目来自一次很直接的验证：**鸿蒙 NEXT 能不能在原生 App 里跑本地大模型？**

早期方向是找 GGUF / llama.cpp 在鸿蒙上的案例，但实测下来，面向鸿蒙原生工程更稳的路线是 MNN：它有移动端推理能力，也已经有 Gemma 4 的 MNN 导出模型。于是这个仓库先把目标收敛到一件事：

> 在 HarmonyOS NEXT 真机上，用原生 App 加载本地 Gemma 4 模型，并完成可交互、可流式输出的聊天。

当前版本不是云端聊天壳子，也不是 WebView；模型文件在设备本地，推理由 App 内的原生层完成。

## 快速开始：从克隆到跑起内置模型

当前推荐流程是：**源码构建安装 App，然后在 App 内按提示下载内置模型**。不再要求新用户先在 PC 上下载模型目录、再用 `hdc file send` 推进沙箱。

### 1. 克隆仓库

```sh
git clone https://github.com/Torry2022/turbo-ai-chat-harmonyos.git
cd turbo-ai-chat-harmonyos
```

如果你想基于原作者仓库开始，也可以替换为上游地址：

```sh
git clone https://github.com/Turbo1123/turbo-ai-chat-harmonyos.git
cd turbo-ai-chat-harmonyos
```

### 2. 用 DevEco Studio 打开并配置签名

1. 使用 DevEco Studio 打开项目根目录。
2. 登录 Huawei 开发者账号。
3. 进入 `File > Project Structure > Signing Configs`。
4. 为默认产品开启自动签名。
5. 确认真机已开启开发者选项和 USB 调试。

`build-profile.json5` 中只保留默认产品使用 `signingConfig` 的绑定；真实证书、profile、私钥路径和密码不应提交到仓库。

### 3. 构建并安装到真机

可以直接在 DevEco Studio 中运行项目，也可以使用命令行：

```sh
hvigor assembleHap --no-daemon
hdc list targets
hdc install -r entry/build/default/outputs/default/entry-default-signed.hap
```

如果本机没有全局 `hvigor`，也可以通过项目依赖运行：

```sh
node ./node_modules/@ohos/hvigor/bin/hvigor.js assembleHap --no-daemon
```

### 4. 在 App 内安装内置模型

首次安装后，仓库和 HAP 都**不包含模型权重**。进入 App 后：

1. 打开“模型”页。
2. 选择 `Gemma 4 E2B` 或 `MiniCPM5-1B`。
3. 点击“加载模型”。
4. 如果 App 检测到内置模型目录缺失或不完整，会弹出“安装内置模型”。
5. 点击“下载并安装”，保持 App 在前台等待下载完成。
6. 下载完成后 App 会继续加载模型，回到“聊天”页即可提问。

内置模型会下载到 App 沙箱目录：

```text
/data/storage/el2/base/haps/entry/files/gemma-4-E2B-it-MNN/
/data/storage/el2/base/haps/entry/files/MiniCPM5-1B-MNN/
```

模型大小约为：Gemma 4 E2B `3.7 GB`，MiniCPM5-1B `625 MB`。请确保设备有足够存储空间和稳定网络。

## 功能

- HarmonyOS NEXT 原生 ArkTS UI
- C++ / N-API 推理桥接
- MNN LLM Runtime 设备端推理
- Gemma 4 / MiniCPM5 MNN 模型切换与加载
- 流式输出
- 多轮上下文记忆
- 图片选择入口
- CPU / 内存状态展示
- 启动后检测内置模型目录，缺失时引导一键下载
- 中文界面、沉浸式布局、底部 Tab

## 截图

| 聊天界面 | 顶部状态 | 输入区 |
| --- | --- | --- |
| ![chat main](docs/images/chat-main.jpeg) | ![chat header](docs/images/chat-header.jpeg) | ![chat input](docs/images/chat-input.jpeg) |

## 当前模型格式说明

这个项目当前主线使用的是 **MNN 模型目录**，不是直接加载 `.gguf`。

内置可选模型：

| 模型 | 默认目录 | 输入能力 |
| --- | --- | --- |
| Gemma 4 E2B | `gemma-4-E2B-it-MNN/` | 文本、图片 |
| MiniCPM5-1B | `MiniCPM5-1B-MNN/` | 文本 |

App 会读取所选模型目录下的 `config.json`。切换模型只会切换当前选中项；点击“加载模型”后才会真正释放旧模型并加载新模型。模型对话模板优先交给 MNN 根据 `llm_config.json` 处理，App 不再默认手写各模型的 Prompt 模板。

推荐内置模型来源：

- ModelScope: [`MNN/gemma-4-E2B-it-MNN`](https://modelscope.cn/models/MNN/gemma-4-E2B-it-MNN)
- ModelScope: [`MNN/MiniCPM5-1B-MNN`](https://modelscope.cn/models/MNN/MiniCPM5-1B-MNN)
- 模型类型：Gemma 4 E2B instruction，MNN 4-bit 量化导出
- 主要入口文件：`config.json`

模型目录需要包含这些文件：

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

MiniCPM5-1B 的内置目录需要包含：

```text
MiniCPM5-1B-MNN/
  config.json
  llm_config.json
  tokenizer.mtok
  llm.mnn
  llm.mnn.weight
  embeddings_int4.bin
```

官方 BF16、GGUF、MLX 权重不能被当前原生 MNN 推理层直接读取。

如果你手里是 GGUF，需要先走转换或另接 llama.cpp 鸿蒙移植层；这个仓库当前没有直接读取 GGUF。

## 直接下载 HAP

Release 会附带可安装的 HAP：

- [Latest Release](https://github.com/Turbo1123/turbo-ai-chat-harmonyos/releases/latest)

安装示例：

```sh
hdc install -r turbo-ai-chat-harmonyos-v0.1.0-signed.hap
```

HAP 不内置模型权重。Gemma 4 E2B 约 3.7 GB，MiniCPM5-1B 约 625 MB；安装 App 后，如果内置模型目录缺失，App 会在加载模型前提示从 ModelScope 下载并安装到 App 沙箱目录。

说明：Release 中的 HAP 是调试签名包。如果你的设备不在签名 profile 内，安装可能失败；这种情况下请从源码打开项目，并在 DevEco Studio 中使用自己的账号开启自动签名后重新构建。

## 备用：PC 侧下载模型

正常情况下，安装 App 后直接按 App 内提示下载内置模型即可。下面的 PC 侧下载方式主要用于调试、离线准备或网络受限场景。

```sh
./scripts/download_gemma4_e2b_mnn.sh
```

默认下载到：

```text
models/gemma-4-E2B-it-MNN/
```

也可以指定目录：

```sh
./scripts/download_gemma4_e2b_mnn.sh /path/to/gemma-4-E2B-it-MNN
```

MiniCPM5-1B 推荐在 App 内从 ModelScope 下载；也可以手动准备 MNN 目录，例如：

```text
models/MiniCPM5-1B-MNN/
```

脚本默认从 ModelScope 下载 Gemma 4 E2B。如果没有 `modelscope` CLI，脚本会使用 Python 的 `modelscope` 包。缺依赖时先安装：

```sh
python3 -m pip install modelscope
```

## 备用：手动推送模型到手机

App 默认读取下面的沙箱路径。正常情况下，App 内下载会自动写入这些目录；下面的 `hdc` 推送方式只作为调试备用。

```text
/data/storage/el2/base/haps/entry/files/gemma-4-E2B-it-MNN/config.json
/data/storage/el2/base/haps/entry/files/MiniCPM5-1B-MNN/config.json
```

这是 App 内看到的沙箱路径。使用 `hdc file send` 时，通常需要推到物理路径：

```text
/data/app/el2/100/base/com.example.gemma4mnn/haps/entry/files/gemma-4-E2B-it-MNN/
```

推荐使用脚本：

```sh
./scripts/push_model_to_device.sh
./scripts/push_model_to_device.sh models/MiniCPM5-1B-MNN
```

如果你的设备不是默认用户 `100`，可以指定：

```sh
USER_ID=100 ./scripts/push_model_to_device.sh
```

指定设备：

```sh
HDC_TARGET=<device-id> ./scripts/push_model_to_device.sh
```

手动推送示例：

```sh
hdc shell "mkdir -p /data/app/el2/100/base/com.example.gemma4mnn/haps/entry/files"
hdc file send models/gemma-4-E2B-it-MNN /data/app/el2/100/base/com.example.gemma4mnn/haps/entry/files/
```

## 从源码构建细节

环境要求：

- DevEco Studio / HarmonyOS SDK
- HarmonyOS NEXT 真机
- 已开启开发者选项和 USB 调试
- Huawei 开发者账号，用于自动签名
- `hdc` 和 `hvigor` 在 `PATH` 中

构建 HAP：

```sh
hvigor assembleHap --no-daemon
```

安装：

```sh
hdc list targets
hdc install -r entry/build/default/outputs/default/entry-default-signed.hap
```

如果你的本机还没有签名配置，请在 DevEco Studio 中：

1. 登录 Huawei 开发者账号。
2. 打开项目。
3. 进入 `File > Project Structure > Signing Configs`。
4. 为默认产品开启自动签名。
5. 重新构建。

`build-profile.json5` 中不会提交真实签名材料、证书路径和密码。

## MNN Runtime

仓库包含当前 Demo 使用的 Harmony arm64 `libMNN.so` 和最小头文件，方便直接构建。

如果你想从 MNN 源码重新构建：

```sh
git clone https://github.com/alibaba/MNN.git ../MNN
./scripts/build_mnn_ohos.sh
./scripts/stage_mnn_ohos.sh
```

`stage_mnn_ohos.sh` 会把产物放到：

```text
entry/src/main/libs/arm64-v8a/libMNN.so
third_party/mnn/include/
```

## 原生接口

ArkTS 通过：

```ts
import entry from 'libentry.so';
```

调用 N-API：

```ts
entry.loadModelAsync(configPath, threadNum, maxNewTokens): Promise<string>
entry.generateChatStream(messages, maxNewTokens, onChunk): Promise<string>
entry.reset(): void
entry.isLoaded(): boolean
```

## Roadmap
- 图片输入接入 Gemma 4 多模态能力
- 更细的 token / 首字延迟 / tokens per second 指标
- release 构建流水线
- GGUF / llama.cpp 路线对比和实验分支

## License

Apache-2.0. MNN 和模型文件遵循各自上游许可证；本仓库不提交大模型权重。
