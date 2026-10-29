# 本地重排 API

重排模型根据问题为候选文本评分，帮助调用方从检索结果中选择更相关的材料。它不生成回答，也不负责检索资料。

## 安装与加载

在“模型 → 重排模型”导入 **Qwen3-Reranker 的完整 MNN 导出目录**，可选择文件夹或 ZIP。普通聊天模型、原始 safetensors 和 GGUF 文件不能替代重排模型。

也可将完整目录推送到应用沙箱后，点击“扫描已推送目录”：

```sh
hdc file send -b com.example.gemma4mnn Qwen3-Reranker-0.6B-MNN /data/storage/el2/base/haps/entry/files/rerank-models/Qwen3-Reranker-0.6B-MNN
```

选择模型后点击“加载当前模型”。切换分类或选中其他条目不会加载、卸载模型；“已加载”标签标出实际驻留的重排模型。更换重排模型或修改运行配置前，请先释放它。聊天模型可继续保留在内存中，设备需要有足够的可用内存。

## 调用

在“API 服务”页开启服务，各接口共用同一地址和 API Key。调用 `/v1/rerank` 前加载重排模型即可，无需加载聊天模型。

`GET /v1/models` 会包含已加载重排模型的 ID。请求中的 `model` 可省略；填写时必须与该 ID 一致。

```sh
curl http://DEVICE_IP:8080/v1/rerank \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"query":"中国的首都是哪里？","documents":["北京是中国的首都。","上海位于长江入海口。"],"top_n":2}'
```

响应格式如下，分数仅作格式示意：

```json
{
  "model": "已加载模型的ID",
  "results": [
    { "index": 0, "relevance_score": 0.95 },
    { "index": 1, "relevance_score": 0.12 }
  ]
}
```

- `query` 是非空问题，`documents` 是 1–64 段非空文本。
- `index` 是文本在输入数组中的位置，从 0 开始；重复文本仍保留各自的位置。
- `relevance_score` 是 MNN Qwen3Reranker 从 yes/no logits 计算的 0–1 分数，用于衡量问题与文本的相关性，不是答案正确率。
- 结果按分数降序排列，同分按输入顺序排列。`top_n` 可省略，默认返回全部；填写时应为 1 到候选数量之间的整数。

## 输入与任务限制

单条输入上限包含模型模板、问题和一段候选文本，默认 2048 tokens，可在模型页配置。每项会单独评分；所有候选通过长度检查后才开始计算。不会静默截断，也不会返回部分成功的结果。HTTP 请求整体上限为 1 MiB。

模型未加载返回 503，输入无效或超长返回 400，模型任务繁忙返回 409，评分失败返回 500。首版不排队；调用方收到忙碌响应后自行决定何时重试。

客户端断连或关闭 API 服务会请求取消，在当前候选计算结束后停止后续计算。原生任务结束前不会提前释放模型或接受另一项重排任务。API 日志不记录问题、候选正文或密钥，重排请求不写入聊天历史。

通用版和实验版提供相同接口。实验版知识库暂不自动调用重排。
