# Runtime status API

Once the app's API server is running, use `GET /turbo/runtime` to read runtime status. This Turbo AI Chat extension is available in both chat and decision service modes and follows the same authentication settings as other endpoints.

```sh
curl http://DEVICE_IP:8080/turbo/runtime -H "Authorization: Bearer <API Key>"
```

Omit the header when API authentication is disabled. Queries remain available during generation, do not load or release models, do not stop inference, and do not increase the generation-request count. Sampling is independent of the visible page; the app and API server must remain running.

## Response fields

| Field | Meaning and units |
| --- | --- |
| `object` | Always `turbo.runtime` |
| `service.target` | `all`: endpoints are available together; each uses its corresponding model |
| `service.inferenceBusy` | Whether an API chat-generation or decision request is active |
| `chatModel.id`, `name` | Selected chat model, separate from the Laya decision model |
| `chatModel.loaded`, `loading`, `generating` | Chat model lifecycle and generation flags |
| `metrics.sampledAt` | Runtime sample time, Unix milliseconds |
| `metrics.appCpuPercent`, `systemCpuPercent` | Application and system CPU percentages; `12.5` means 12.5% |
| `metrics.pssWithSwapBytes` | `Pss + SwapPss` in bytes, including swapped pages, separate from the RSS shown on the Monitor page |
| `metrics.rssBytes` | Resident set size in bytes, used by the Monitor page and chat memory indicator; counts shared pages in full |
| `metrics.swapBytes` | Swapped anonymous private pages in bytes; `null` below API 24. This does not measure storage consumption |
| `metrics.nativeHeapAllocatedBytes`, `nativeHeapTotalBytes` | Allocator-reported allocated and total native heap bytes, not total model memory |
| `metrics.systemMemTotalBytes`, `systemMemAvailableBytes` | Total and available system memory in bytes |
| `metrics.batteryTemperatureC` | Battery temperature in Celsius, not CPU die temperature |
| `metrics.threadCount` | All application threads, not the configured inference-thread count |
| `storage.sampledAt` | Storage sample time, Unix milliseconds |
| `storage.appBytes` | Application package, data and cache bytes, including other installed models |
| `storage.currentModelBytes` | Bytes in the selected chat model directory, or 0 if the directory does not exist |

## Sampling and errors

Poll every 2 seconds. Runtime samples may be reused for up to 1 second and storage samples for up to 30 seconds; check their separate timestamps. The Monitor page and endpoint share sampling and unit-conversion logic. Successful polls do not produce individual API log entries.

Invalid authentication returns `401`. Collection failures return `503` with `runtime_unavailable`, rather than substituting zero values. Responses contain no API keys, prompts, answers or model paths.
