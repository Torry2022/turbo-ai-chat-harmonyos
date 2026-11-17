# 模型生成参数的来源与更新

模型默认生成参数由仓库配置、App 预设和人工维护的目录配置共同确定。本文说明目录发布工具的取值规则，以及参数更新在 App 中的生效方式。

## 参数读取规则

目录发布工具按字段依次读取同一固定提交的 `config.json`、`generation_config.json`，缺失字段使用下表中的兜底值。文件和参数均以条目固定的仓库版本为准。

| App 字段 | 仓库字段（从左到右优先） | 兜底值 |
| --- | --- | --- |
| temperature | temperature | 0.6 |
| topP | top_p、topP | 0.9 |
| topK | top_k、topK | 40 |
| repetitionPenalty | repetition_penalty、penalty | 1.05 |
| frequencyPenalty | frequency_penalty | 0 |
| presencePenalty | presence_penalty | 0 |
| penaltyWindow | penalty_window | 256 |

同一配置内优先读取 snake_case 字段，再读取兼容别名。空值继续查找下一来源，非数值或非有限数值会报错。`generation_config.json` 显式设置 `do_sample: false` 时，发布工具要求人工确认与 App 解码方式的兼容性。

映射范围为 App 已支持的字段。`sampler` 链、`min_p`、beam search 等配置需要另行核对。最大输出长度独立设置，目录未指定 `maxNewTokens` 时，App 默认使用 512 tokens。上下文消息条数与输出 token 上限分别控制。

仓库配置、原作者推荐参数和 App 预设可能不同。查阅官方建议时，应同时确认模型版本、输入类型和思考模式。

## 更新何时生效

| 配置来源 | 生效方式 |
| --- | --- |
| App 内置模型 | 使用 `MODEL_PROFILES` 中的预设，由 App 更新维护 |
| 尚未安装的市场模型 | 使用当前目录配置，安装时保存条目快照 |
| 已保存安装快照的市场模型 | 优先使用与本地模型配套的快照配置 |
| 当前生成参数面板 | 切换模型或重置参数时读取默认值，目录刷新保留当前手动设置 |

维护目录时，应区分文件版本更新与生成参数调整。已安装模型的参数更新需要保留与文件版本的对应关系，并尊重用户的手动设置。

## 保留的模型配置

以下条目采用人工维护的配置，重新生成目录时需要保留这些选择。表内顺序为温度、Top-P、Top-K、重复惩罚和惩罚窗口。

| 模型 | 目录配置 | 维护依据 |
| --- | --- | --- |
| Qwen3-VL-8B-Instruct | 0.6 / 0.9 / 40 / 1.05 / 256 | 沿用通过文本、图片及模型生命周期验证的 App 配置 |
| MiniCPM4-8B | 0.6 / 0.9 / 40 / 1.05 / 256 | 与已验证的导入默认参数、提示词和单轮上下文配套维护 |
| MiniCPM5-2B | 1.0 / 0.95 / 40 / 1.0 / 256 | 温度和 Top-P 参考原作者建议，Top-K 与惩罚窗口采用 App 已验证配置 |

Qwen3-VL 的官方建议区分视觉和纯文本输入。MiniCPM4 的官方示例与表中 App 配置也有差异。维护时需结合对应模型的说明核对取值。[Qwen3-VL 模型卡](https://huggingface.co/Qwen/Qwen3-VL-8B-Instruct#generation-hyperparameters)、[MiniCPM4 使用说明](https://huggingface.co/openbmb/MiniCPM4-8B#usage)、[MiniCPM5-2B 使用说明](https://huggingface.co/openbmb/MiniCPM5-2B#quickstart)

## 调整配置

使用 `model_catalog.py add` 更新同 ID 条目时，工具会重新生成运行配置。先通过 `--dry-run` 比较差异，再保留或调整人工维护的字段。

比较候选参数时，应固定模型文件版本、设备、提示词、思考模式和输出预算，并分别检查回答内容、重复输出及结束原因。Qwen3 和 MiniCPM5-1B 的预设应分别按具体型号和思考模式维护。

思考模式与生成参数分别设置。对 Qwen3、MiniCPM5 等支持思考的模型，应结合实际模板和所选模式查阅建议参数。[Qwen3 使用建议](https://huggingface.co/Qwen/Qwen3-0.6B#best-practices)、[MiniCPM5-1B 使用说明](https://huggingface.co/openbmb/MiniCPM5-1B#quickstart)
