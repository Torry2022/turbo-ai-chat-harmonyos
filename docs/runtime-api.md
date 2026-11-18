# 运行状态 API

启动 App 的 API 服务后，使用 `GET /turbo/runtime` 读取运行状态。它是 Turbo AI Chat 的扩展接口，聊天服务和决策服务均可使用，鉴权设置与其他端点一致。

```sh
curl http://设备IP:8080/turbo/runtime -H "Authorization: Bearer <API Key>"
```

未启用 API 认证时省略请求头。生成期间仍可查询，不会加载或释放模型、停止生成，也不计入生成请求数。采样不依赖当前页面，但仍受 App 与 API 服务的运行状态约束；退出 App 或停止服务后不可访问。

## 返回字段

| 字段 | 含义与单位 |
| --- | --- |
| `object` | 固定为 `turbo.runtime` |
| `service.target` | `all`：各接口同时开放，分别使用对应模型 |
| `service.inferenceBusy` | API 是否正在处理对话、决策、向量或重排请求 |
| `chatModel.id`、`name` | 当前选择的聊天模型，不代表 Laya 决策模型 |
| `chatModel.loaded`、`loading`、`generating` | 聊天模型是否已加载、正在加载、正在生成 |
| `chatModel.requestedThreads`、`rerankModel.requestedThreads`、`embeddingModel.requestedThreads` | 对应已加载模型请求的推理线程数；未加载时为 0 |
| `chatModel.actualCpuThreads`、`rerankModel.actualCpuThreads`、`embeddingModel.actualCpuThreads` | 加载完成时从现有 CPU runtime 读取的最大并行宽度；未加载时为 0。不是每个算子同时运行的线程数，也不是 App 线程总数 |
| `embeddingModel` | 向量模型的 ID、名称、加载与运行状态，以及请求线程数和实际 CPU 并行上限 |
| `lastChatGeneration` | 最近一次返回结果的 API 对话生成记录，含结束原因、耗时、Token 和实际请求配置；新请求开始时清空，应用重启后不保留 |
| `metrics.sampledAt` | 本次运行指标的采样时间，Unix 毫秒 |
| `metrics.appCpuPercent`、`systemCpuPercent` | 应用与系统 CPU 使用率，百分数；例如 `12.5` 表示 12.5% |
| `metrics.pssWithSwapBytes` | `Pss + SwapPss`，字节，包含换出部分，独立于监控页采用的 RSS |
| `metrics.rssBytes` | 常驻内存 RSS，字节；用于监控页“常驻内存”和聊天页“应用内存”，共享页按完整大小计入 |
| `metrics.swapBytes` | 进程换出的匿名私有页总量，字节；API 24 以下为 `null`，不能据此判断占用了多少存储空间 |
| `metrics.nativeHeapAllocatedBytes`、`nativeHeapTotalBytes` | 原生内存分配器记录的已分配量、堆总量，字节，不等同于模型总内存 |
| `metrics.systemMemTotalBytes`、`systemMemAvailableBytes` | 系统总内存、可用内存，字节 |
| `metrics.batteryTemperatureC` | 电池温度，摄氏度，不是 CPU 芯片温度 |
| `metrics.threadCount` | App 线程总数，不是模型的推理线程设置 |
| `storage.sampledAt` | 存储统计的采样时间，Unix 毫秒 |
| `storage.appBytes` | 应用本体、数据与缓存总量，字节，包含其他已安装模型 |
| `storage.currentModelBytes` | 当前聊天模型目录的文件总量，字节；目录不存在时为 0 |

## 采样与错误

建议每 2 秒请求一次。运行指标最多复用 1 秒内的快照，存储统计最多复用 30 秒；分别使用两组 `sampledAt` 判断数据时间。监控页与接口共用采样和单位换算逻辑。正常采样不逐条写入 API 日志。

认证失败返回 `401`；采集失败返回 `503` 和 `runtime_unavailable`，不会用 0 伪装成正常读数。读取时不返回 API Key、提示词、回答或模型文件路径。

`lastChatGeneration.perfMetrics.configuration` 在请求开始时保存生成参数、模型名称及标识、线程、配置与运行库指纹、应用版本、机型和系统版本。该记录不含问题、回答、图片、API Key 或会话缓存标识；旧运行和缺失字段不补填推测值。请求在输入准备或 Native 调用中抛错时，此字段保持缺省。

配置指纹 `configurationSha256` 覆盖实际配置文本，文件清单指纹 `fileManifestSha256` 覆盖目录内文件的相对路径、大小与修改时间。清单在加载时读取并缓存，便于识别本机文件变更。权重内容的逐字节校验另需内容哈希。

模型通过应用下载且安装快照中保存了固定提交时，`sourceRepository` 和 `sourceRevision` 记录该次下载的仓库与提交。自行导入、修改配置路径或缺少安装快照时，这两项保持缺省。来源版本取自已安装快照。
