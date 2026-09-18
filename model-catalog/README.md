# 在线模型广场目录

在线目录分为两条兼容通道。升级 MNN 的新版 App 读取 `catalog-v2.json`；使用 MNN 3.6.0 的旧版 App 继续读取 `catalog.json`。App 始终保留安装包内置目录；在线文件只需要声明新增模型、需要覆盖的既有条目，以及需要下架的非预置条目。

`v2` 表示运行时兼容通道，不是 JSON 格式版本；两份文件的 `schemaVersion` 都是 1，`catalogVersion` 各自递增。新目录从旧目录复制已有条目，后续互不自动同步。需要新 MNN 算子的模型只能加入新目录，不能依靠旧客户端不认识的最低版本字段进行隔离。发布器只校验目录结构，不能替代两种运行时的真机验证。

新版使用独立的目录缓存和已安装模型快照。首次读取时迁移旧安装快照（不移动模型文件、不回写旧快照），因此升级后旧模型仍可管理，新模型记录也不会经共享快照进入降级后的旧版 App。降级期间新增的安装记录不会再次自动合并到新版快照；手动导入模型仍由用户自行确认运行时兼容性。

## App 版本要求

每个模型可声明整数 `minAppVersionCode`，与安装包自身的 `versionCode` 比较；它与 `catalogVersion` 无关，也不能按版本名称的字符串大小比较。当前新版为 v1.10.1 / 1100100。要求不满足时条目仍显示，提示“需升级 App”并禁用下载；实际下载及目录模型加载入口也检查，目录缓存和安装快照保留此字段。读取安装包版本失败时，有要求的模型暂不可下载或加载。已安装快照按安装时的文件及版本要求判断，不用在线新权重的要求替换旧权重记录。

旧数据缺少字段时保持兼容读取；显式 null、字符串、负数、小数等无效值会使目录校验失败并保留已有目录。发布器新增或更新条目必须指定最低版本，不自动猜测。导入模型不属于这套目录声明的验证范围。

本次对新通道的全部条目补齐要求，旧通道保持原样：

| 范围 | 门槛 | 依据与含义 |
| --- | --- | --- |
| 安装包已有的 9 项模型 | 1070000（v1.7.0） | 在线目录初始实现已包含这些条目，以该功能版本作为目录维护门槛，不主张模型不能在更早版本运行。 |
| 新通道复制的前 8 项增量模型 | 1100000（v1.10.0） | 采用既有通用版验证基线作为保守分发门槛；不声称这是历史上绝对最早可用版本。 |
| Qwen2.5-7B、Qwen2-7B、MiniCPM4-8B | 1100100（v1.10.1） | 2026-09-08 停止/释放回归依赖 3686042 修复；此前修复包与正式包共用 1.10.0 号，首次用独立发布版本区分。旧包正常生成不代表通过该完整回归。 |
| MiniCPM5-2B | 1100100（v1.10.1） | 依赖此次新 MNN 算子支持。 |

这些数值是维护者承诺支持的分发下限，不是算法推断的最早兼容版本，也不保证任意设备内存足够。若要降低保守门槛，应先补旧版本验证记录。更新权重、revision 或运行配置时需重新评估，不应机械保留旧要求。

旧 App 不认识字段，因此仍必须保留 `catalog.json` 与 `catalog-v2.json` 隔离。发布器拒绝把要求高于 1100000 的新条目写到旧目录；这个保护不能证明旧目录对更早所有 App 都兼容，维护旧目录仍须检查目标旧包。未来识别字段的客户端共用新通道，通常无需为每次运行时升级另开目录。

## Actions 操作

日常维护不需要手写 JSON：

1. 打开仓库的 **Actions → Publish model catalog → Run workflow**。
2. `channel` 默认选择 `current`（新目录）；维护旧目录时明确选择 `legacy`，并先验证 MNN 3.6.0 兼容性。`operation` 选择 `add_or_update`、`hide` 或 `validate`。
3. 新增或更新模型时填写 ModelScope 模型链接和 `min_app_version_code`（例如 `1100100`）；版本要求必须由维护者确认，不能从仓库名称自动推断。其余字段按需覆盖。
4. 下架模型时只填写 `model_id`。
5. 运行后，工作流会执行测试、读取 ModelScope 文件清单、固定到具体提交、生成并校验目录，然后只将选中通道的目录文件提交到 `main`。

工作流只允许修改这一份目录文件；如果 `main` 在运行期间发生变化或生成器触碰其他文件，发布会失败并要求重新运行。工作流由手动表单触发，自己的提交不会递归触发下一次发布。

注意：`add_or_update` 会重新生成运行配置，不自动保留人工调整过的参数。已有条目应先在本地使用 `--dry-run` 比较差异；有意保留的实测配置须人工维护，不要直接用 Actions 覆盖。当前已确认的条目见[生成参数说明](generation-defaults.md#历史依据复核与处理结论)。

## Fork 与二次开发

发布器只负责更新当前仓库中选中的目录，不会自动改变 App 请求在线目录的地址。当前 App 在 [`ModelCatalogService.ets`](../entry/src/main/ets/services/ModelCatalogService.ets) 中固定读取：

```text
https://raw.githubusercontent.com/Torry2022/turbo-ai-chat-harmonyos/main/model-catalog/catalog-v2.json
```

因此，直接 Fork 或克隆后构建的 App 仍会读取 Torry2022 仓库的模型目录。在 Fork 中运行 `Publish model catalog` 只会更新该 Fork 自己的目录，不会影响本仓库；若要让二次开发版本维护独立模型广场，需要将 `REMOTE_MODEL_CATALOG_URL` 改为：

```text
https://raw.githubusercontent.com/<仓库所有者>/<仓库名>/<默认分支>/model-catalog/catalog-v2.json
```

修改地址后需要重新构建 App。此后只更新该 Fork 的目录文件即可发布兼容模型条目，不必为每次目录更新重新构建安装包。

## 本地发布器

发布器只依赖 Python 标准库，默认操作新目录：

```powershell
# 校验当前目录
python scripts/model_catalog.py validate

# 查看当前远程增量条目
python scripts/model_catalog.py list

# 根据 ModelScope 仓库自动新增或更新模型
python scripts/model_catalog.py add https://modelscope.cn/models/组织/仓库 --min-app-version-code 1100100

# 只生成和校验，不写入目录
python scripts/model_catalog.py add 组织/仓库 --min-app-version-code 1100100 --dry-run

# 下架普通市场模型
python scripts/model_catalog.py hide 模型ID

# 显式检查旧目录；维护旧目录时同样需要此参数
python scripts/model_catalog.py --catalog model-catalog/catalog.json validate
```

新增模型时，发布器会自动读取仓库文件名和精确大小、排除 README 等非运行文件、解析文本/图片能力和常用生成参数、生成运行配置、递增 `catalogVersion` 并更新 `publishedAt`。使用 `master`、分支或标签作为输入时，最终写入目录的是 ModelScope 返回的具体提交哈希。

生成参数兼容新旧字段名，并以同一提交的 `config.json` 优先、`generation_config.json` 次之，缺项使用 App 兜底值。内置预设和已安装快照不会随目录刷新自动覆盖，详见[生成参数来源、更新边界与审计结果](generation-defaults.md)。

自动推断不合适时可使用 `--id`、`--directory-name`、`--display-name`、`--description`、`--supports-image`、`--system-prompt` 和 `--context-message-limit` 覆盖。运行 `python scripts/model_catalog.py add --help` 可查看完整参数。

更新规则：

1. 每次发布目录时递增 `catalogVersion` 并更新 `publishedAt`。
2. `items` 中相同 `id` 会覆盖安装包内置的市场信息；全新 `id` 必须提供 `runtime`。
3. `hiddenIds` 可以下架普通市场模型，但不能移除固定展示的预置模型。
4. `source.type` 当前只允许 `modelscope`；`repo` 使用 `组织/仓库`，`revision` 必须固定到提交哈希。
5. 每个条目至少声明 `config.json` 和 `llm_config.json`，所有路径必须是模型目录内的相对路径。
6. 新市场模型安装成功后，App 会保存安装快照；以后即使目录下架，该模型仍可离线加载和删除。

首次上线须先将 `catalog-v2.json` 发布到 `main` 并确认地址可访问，再发布读取它的新版 App。不要删除或重定向旧目录，否则旧版会失去在线更新能力或误取不兼容模型。仅生成本地目录不代表线上已发布。

维护代码后的本地检查：`python -m unittest scripts.test_model_catalog` 验证发布器；`node scripts/test_catalog_storage.cjs <typescript.js 路径>` 使用 TypeScript 编译器执行实际 ArkTS 服务代码、以内存文件系统验证缓存隔离和快照迁移。DevEco 自带的编译器位于 `tools/hvigor/hvigor/node_modules/typescript/lib/typescript.js`。后者不替代完整 ArkTS 构建和真机验收。

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
