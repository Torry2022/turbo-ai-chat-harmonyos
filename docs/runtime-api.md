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
| `service.target` | 当前 API 服务类型：`chat` 或 `decision` |
| `service.inferenceBusy` | API 是否正在处理聊天生成或决策请求 |
| `chatModel.id`、`name` | 当前选择的聊天模型，不代表 Laya 决策模型 |
| `chatModel.loaded`、`loading`、`generating` | 聊天模型是否已加载、正在加载、正在生成 |
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
