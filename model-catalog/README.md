# 在线模型广场目录

`catalog.json` 是 Turbo AI Chat 通用版默认读取的在线模型广场增量目录。App 始终保留安装包内置目录；此文件只需要声明新增模型、需要覆盖的既有模型条目，以及需要下架的非预置条目。

## 推荐维护方式：GitHub Actions 表单

日常维护不需要手写 JSON：

1. 打开仓库的 **Actions → Publish model catalog → Run workflow**。
2. `operation` 选择 `add_or_update`、`hide` 或 `validate`。
3. 新增模型时填写 ModelScope 模型链接；其余字段只有需要覆盖自动推断值时才填写。
4. 下架模型时只填写 `model_id`。
5. 运行后，工作流会执行测试、读取 ModelScope 文件清单、固定到具体提交、生成并校验目录，然后直接提交 `model-catalog/catalog.json` 到 `main`。

工作流只允许修改这一份目录文件；如果 `main` 在运行期间发生变化或生成器触碰其他文件，发布会失败并要求重新运行。工作流由手动表单触发，自己的提交不会递归触发下一次发布。

## Fork 与二次开发

发布器只负责更新当前仓库中的 `model-catalog/catalog.json`，不会自动改变 App 请求在线目录的地址。当前 App 在 [`ModelCatalogService.ets`](../entry/src/main/ets/services/ModelCatalogService.ets) 中固定读取：

```text
https://raw.githubusercontent.com/Torry2022/turbo-ai-chat-harmonyos/main/model-catalog/catalog.json
```

因此，直接 Fork 或克隆后构建的 App 仍会读取 Torry2022 仓库的模型目录。在 Fork 中运行 `Publish model catalog` 只会更新该 Fork 自己的 `catalog.json`，不会影响本仓库；若要让二次开发版本维护独立模型广场，需要将 `REMOTE_MODEL_CATALOG_URL` 改为：

```text
https://raw.githubusercontent.com/<仓库所有者>/<仓库名>/<默认分支>/model-catalog/catalog.json
```

修改地址后需要重新构建 App。此后只更新该 Fork 的目录文件即可发布兼容模型条目，不必为每次目录更新重新构建安装包。

## 本地发布器

发布器只依赖 Python 标准库：

```powershell
# 校验当前目录
python scripts/model_catalog.py validate

# 查看当前远程增量条目
python scripts/model_catalog.py list

# 根据 ModelScope 仓库自动新增或更新模型
python scripts/model_catalog.py add https://modelscope.cn/models/组织/仓库

# 只生成和校验，不写入 catalog.json
python scripts/model_catalog.py add 组织/仓库 --dry-run

# 下架普通市场模型
python scripts/model_catalog.py hide 模型ID
```

新增模型时，发布器会自动读取仓库文件名和精确大小、排除 README 等非运行文件、解析文本/图片能力和常用生成参数、生成运行配置、递增 `catalogVersion` 并更新 `publishedAt`。使用 `master`、分支或标签作为输入时，最终写入目录的是 ModelScope 返回的具体提交哈希。

自动推断不合适时可使用 `--id`、`--directory-name`、`--display-name`、`--description`、`--supports-image`、`--system-prompt` 和 `--context-message-limit` 覆盖。运行 `python scripts/model_catalog.py add --help` 可查看完整参数。

更新规则：

1. 每次发布目录时递增 `catalogVersion` 并更新 `publishedAt`。
2. `items` 中相同 `id` 会覆盖安装包内置的市场信息；全新 `id` 必须提供 `runtime`。
3. `hiddenIds` 可以下架普通市场模型，但不能移除固定展示的预置模型。
4. `source.type` 当前只允许 `modelscope`；`repo` 使用 `组织/仓库`，`revision` 必须固定到提交哈希。
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
    "revision": "0123456789abcdef0123456789abcdef01234567"
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
