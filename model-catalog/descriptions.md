# 模型卡片简介

[model_descriptions_zh.json](../entry/src/main/resources/rawfile/model_descriptions_zh.json) 为模型广场提供中文简介。这个文件既随 App 打包，也作为在线描述目录；修改文字不需要重新转换或下载模型。

## 更新方式

首次使用该机制需要安装包含此功能的 App。此后将描述文件更新到本仓库 `main`，已有客户端会在启动时后台刷新目录，或点击广场“刷新”时获取新描述，不必等待 App 发版。

- `descriptionVersion` 是描述文件自己的递增整数，与 App 版本和官方目录版本无关。每次发布描述修改时加一，同时更新 `publishedAt`。
- `entries` 是完整清单。每项用精确的 ModelScope `组织/仓库` 匹配，忽略大小写；同名的不同尺寸、量化版和训练版本分别维护，不按厂商名称批量覆盖。
- App 使用本地缓存与安装包内版本中较新的有效描述。联网失败、远程内容损坏或版本倒退时保留已有内容；官方新增但尚未编写简介的模型继续显示目录默认描述。
- 删除一个条目并递增版本，可让该模型恢复默认描述。描述更新只替换简介，不修改能力标签、下载文件、生成参数、兼容要求或已安装模型文件。

在线地址在 `ModelCatalogService.ets` 的 `DESCRIPTION_URL` 和 `DESCRIPTION_API_URL` 中配置，分别使用 GitHub Raw 与 Contents 接口。二次开发版本如需自行维护，应同时修改这两个地址。

## 文案与来源

每项保留 `sources` 供维护者复核，不在模型卡片中展示。优先使用该版本的官方模型卡与技术报告，参考有明确模型版本和评测方法的独立评测。同厂商、同系列保持相近句式，优先说明用途、输入类型和版本差异。

简介一般控制在 30～45 字，最多 50 字；不重复卡片已有的名称、大小和标签，不写宣传排名，也不把其他硬件上的速度、内存或完整上下文长度当作本 App 的运行表现。不同量化与推理后端的评测需要分别判断，缺少可信对照时只保留能够核实的定位和能力。

卡片继续静止显示两行，超出时省略，不自动滚动。

```json
{
  "schemaVersion": 1,
  "descriptionVersion": 1,
  "publishedAt": "2026-11-03T06:00:00Z",
  "entries": [
    {
      "repo": "MNN/Qwen3-4B-Instruct-2507-MNN",
      "description": "Qwen3 指令优化版，支持多语言问答、写作与代码任务，直接输出回答。",
      "sources": ["https://huggingface.co/Qwen/Qwen3-4B-Instruct-2507"]
    }
  ]
}
```

本地校验：

```powershell
node scripts/test_model_descriptions.cjs <typescript.js 路径>
node scripts/test_catalog_storage.cjs <typescript.js 路径>
```

前者检查数据格式、内置条目覆盖、长度和资源读取；后者验证在线更新、缓存恢复、默认描述回退及安装快照隔离。
