# 在线模型市场目录

`catalog.json` 是 Turbo AI Chat 通用版默认读取的在线模型市场增量目录。App 始终保留安装包内置目录；此文件只需要声明新增模型、需要覆盖的既有市场条目，以及需要下架的非预置条目。

更新规则：

1. 每次发布目录时递增 `catalogVersion` 并更新 `publishedAt`。
2. `items` 中相同 `id` 会覆盖安装包内置的市场信息；全新 `id` 必须提供 `runtime`。
3. `hiddenIds` 可以下架普通市场模型，但不能移除固定展示的预置模型。
4. `source.type` 当前只允许 `modelscope`；`repo` 使用 `组织/仓库`，`revision` 应固定到不可变提交或标签。
5. 每个条目至少声明 `config.json` 和 `llm_config.json`，所有路径必须是模型目录内的相对路径。
6. 新市场模型安装成功后，App 会保存安装快照；以后即使目录下架，该模型仍可离线加载和删除。

新增模型示例：

```json
{
  "id": "example-model",
  "directoryName": "Example-Model-MNN",
  "displayName": "Example Model",
  "shortName": "Example",
  "description": "适用于端侧文本对话的示例模型。",
  "provider": "Example",
  "supportsImage": false,
  "capabilities": ["文本"],
  "source": {
    "type": "modelscope",
    "repo": "Example/Example-Model-MNN",
    "revision": "固定提交或标签"
  },
  "files": [
    { "relativePath": "config.json", "sizeBytes": 100 },
    { "relativePath": "llm_config.json", "sizeBytes": 100 },
    { "relativePath": "tokenizer.txt", "sizeBytes": 100 },
    { "relativePath": "llm.mnn", "sizeBytes": 100 },
    { "relativePath": "llm.mnn.weight", "sizeBytes": 100 }
  ],
  "runtime": {
    "systemPrompt": "你是运行在本地设备上的 Example Model。请使用简体中文回答。",
    "contextMessageLimit": 6,
    "generationDefaults": {
      "temperature": 0.6,
      "topP": 0.9,
      "topK": 40,
      "repetitionPenalty": 1.05,
      "frequencyPenalty": 0,
      "presencePenalty": 0,
      "penaltyWindow": 256
    }
  }
}
```

远程目录只能分发当前 App 和 MNN Runtime 已支持的文本或图片 MNN 模型。需要新的原生算子、预处理流程、推理模态或更高版本 MNN Runtime 时，仍需升级 App。
