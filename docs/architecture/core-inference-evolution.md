# 核心推理链演进说明

Turbo AI Chat 基于 [`Turbo1123/turbo-ai-chat-harmonyos`](https://github.com/Turbo1123/turbo-ai-chat-harmonyos) 开发。上游仓库在 [`f946a84`](https://github.com/Turbo1123/turbo-ai-chat-harmonyos/commit/f946a842c371fd2d00e0e33369ae8efc7b564474) 中实现了 Gemma 4 的端侧文本生成：ArkTS 通过 N-API 调用 C++，再由 MNN Runtime 加载模型并完成流式输出和多轮对话。

本仓库保留了这条基础链路，并在后续开发中补充了多模型加载、图片输入、生成控制、性能统计、模型管理和局域网 API 服务。本文记录这些改动在当前版本中的实现方式。

## 多模型加载

上游实现主要面向 Gemma 4，模型目录、提示词格式和 native 类名都带有较强的单模型特征。接入 Qwen、MiniCPM 等模型后，加载流程改为以 MNN 模型目录为单位，不再由 ArkTS 固定某一种模型的提示词模板。

当前流程会先检查模型目录，再读取其中的 `llm_config.json`。对话模板、停止符、视觉配置和生成参数优先采用模型自身的配置；兼容代码只处理少数仍在使用的旧目录格式。预置模型、从模型广场下载的模型和用户导入的模型最终通过同一套接口加载。

C++ 推理类也由 `GemmaRunner` 更名为 `MnnLlmRunner`。这个名称对应其实际职责：加载并运行兼容 MNN `Transformer::Llm` 的模型目录，而不是绑定某个具体模型。

## 图片输入链路

上游界面具备图片选择入口，但所选图片没有传入 native 推理层。本仓库补齐了从图片 URI 到 MNN 视觉输入的完整路径：

```text
图片 URI
-> ArkTS 读取并解码图片
-> ArrayBuffer 传入 N-API
-> C++ 构造图像张量与 PromptImagePart
-> MNN 执行多模态推理
```

图片的目标尺寸由模型目录中的视觉配置决定，缩放交给 MNN 处理。因此，同一条调用链可以适配 Gemma 4、Qwen3-VL 等视觉配置不同的模型。

## 生成控制与性能数据

生成接口除了返回文本，还需要向 ArkTS 提供生成状态。当前 native 接口会传递和返回以下信息：

- 最大输出长度、温度、Top-K、Top-P 等采样参数；
- 按 UTF-8 边界处理的流式文本；
- 用户主动停止请求；
- `eos`、达到最大长度、用户停止、超时和内部错误等停止原因；
- 输入、输出 token 数量及生成耗时。

ArkTS 根据这些结果更新消息状态，并计算 TTFT、TPOT 和 tokens/s。被用户停止或因异常中断的回答会按停止原因处理，避免将不完整内容误当作正常回答继续参与上下文。

## 模型安装、导入与切换

早期版本要求开发者将模型手动推送到固定的沙箱目录。当前版本支持三种模型来源：随应用配置的预置模型、模型广场提供的在线模型，以及用户导入的 MNN 模型目录。

模型在加载前会经过目录预检，确认 `llm_config.json` 及其引用的权重、分词器、视觉文件和对话模板是否完整。加载失败后会释放 native 状态，避免残留实例影响下一次加载。

下载、导入、切换、删除和推理共用统一的忙碌状态约束。例如，模型正在生成内容时不能同时删除其目录，切换模型前也会先结束并释放当前实例。模型广场的在线目录只保存模型信息和下载地址，权重文件仍由 ModelScope 等模型托管平台提供。

## 局域网 API 服务

`OpenAiApiServer` 使用 HarmonyOS 的 `TCPSocketServer` 在设备上监听端口，将 OpenAI 兼容请求转换为现有的文本生成调用。服务支持查询当前模型，并通过 Chat Completions API 或 Responses API 返回普通 JSON 和 SSE 流式结果。

API 请求与 App 内对话共用同一个 `MnnLlmRunner` 实例和忙碌状态，因此同一时间只执行一个生成任务。第一版不自动切换模型，也不接收图片或工具调用。模型输出包含 `<think>` 时，Chat Completions API 通过 `reasoning_content` 返回思考过程，Responses API 使用独立 reasoning 输出项，最终回答仍保留在常规文本字段中。

服务仅在用户手动开启后监听局域网地址，并可使用 Bearer API Key 鉴权。关闭服务或断开正在生成的客户端连接时，停止请求会继续传递到 native 推理层。

## 当前调用关系

```text
ChatTab / ModelTab / MonitorTab          Cherry Studio 等局域网客户端
                |                                   |
          ChatViewModel <---------------- OpenAiApiServer
      |-- GenerationWorkflow -- ImagePayloadService
      |-- ModelLifecycleService
      |     |-- ModelDirectoryPreflightService
      |     |-- BuiltinModelInstallService
      |     `-- ModelImportService
      `-- NativeInferenceService
                |
        N-API Bridge (libentry.so)
                |
     MnnLlmRunner (mnn_llm_runner.cpp)
        |          |           |
      文本      原始 Prompt    图片
                |
       MNN Runtime 3.6.0
                |
           CPU Backend
```

各层的职责如下：

- `ChatViewModel` 保存页面共享的模型、会话和生成状态；
- `GenerationWorkflow` 组织单次生成流程，并协调文字与图片输入；
- `ModelLifecycleService` 处理模型加载、切换、删除及相关状态检查；
- `NativeInferenceService` 封装 ArkTS 对 N-API 的调用；
- `OpenAiApiServer` 处理 HTTP、Bearer 鉴权和 OpenAI 协议转换；
- N-API 负责参数转换、异步任务和流式回调；
- `MnnLlmRunner` 直接调用 MNN，返回生成文本、停止原因和 token 统计。

## 关键提交

- [`12da6ad`](https://github.com/Torry2022/turbo-ai-chat-harmonyos/commit/12da6ad)：将图片数据接入 MNN 视觉推理；
- [`cb00398`](https://github.com/Torry2022/turbo-ai-chat-harmonyos/commit/cb00398)：加入模型切换并支持 MiniCPM5；
- [`0a418d9`](https://github.com/Torry2022/turbo-ai-chat-harmonyos/commit/0a418d9)：支持导入其他 MNN 模型；
- [`27adf57`](https://github.com/Torry2022/turbo-ai-chat-harmonyos/commit/27adf57)：完善异常处理、资源释放和采样参数传递；
- [`5ddf5f9`](https://github.com/Torry2022/turbo-ai-chat-harmonyos/commit/5ddf5f9)：整理模型生命周期和生成控制；
- [`b9de26a`](https://github.com/Torry2022/turbo-ai-chat-harmonyos/commit/b9de26a)：补充停止原因和 token 统计；
- [`b17106c`](https://github.com/Torry2022/turbo-ai-chat-harmonyos/commit/b17106c)：将页面中的推理逻辑拆分到状态层和服务层；
- [`0e5c138`](https://github.com/Torry2022/turbo-ai-chat-harmonyos/commit/0e5c138)：将 HarmonyOS 端的 MNN Runtime 升级至 3.6.0。

从上游基线到当前 `main` 分支的完整代码差异可通过 [`f946a84...main`](https://github.com/Torry2022/turbo-ai-chat-harmonyos/compare/f946a842...main) 查看。

## 兼容性说明

本次核心代码整理更改了 `GemmaRunner`、CMake 工程名和 native 内部任务名，但没有修改 ArkTS 使用的 N-API 方法，因此现有 ArkTS 调用无需迁移。

应用的 `bundleName` 仍为 `com.example.gemma4mnn`。HarmonyOS 使用它识别应用及其沙箱数据；如果现在修改，设备会将新版识别为另一个应用，原有数据也不会自动沿用，因此本次整理继续保留该名称。

## English summary

The upstream project established the initial ArkTS → N-API → C++ → MNN pipeline for Gemma 4 text generation on HarmonyOS. This repository retains that foundation and extends it with compatible multi-model loading, native image input, generation control, performance metrics, model lifecycle management, and an OpenAI-compatible LAN API.

Model-specific settings are read primarily from each MNN directory. Text, raw-prompt, image, and LAN API requests share the same native boundary, while generation results include cancellation state, stop reason, and token counts. The API server exposes the currently loaded model through `/v1/models`, `/v1/chat/completions`, and `/v1/responses`. The internal runner was renamed from `GemmaRunner` to `MnnLlmRunner` to reflect its current responsibility. Public N-API methods and the existing application identity remain unchanged.
