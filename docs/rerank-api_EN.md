# Local reranking API

A reranking model scores candidate passages against a query so callers can select relevant material from retrieval results. It neither searches a corpus nor generates an answer.

## Install and load

Open **Models → Reranking models** and import a complete **Qwen3-Reranker MNN export** using the folder or ZIP importer. Ordinary chat models, original safetensors weights and GGUF files are not supported substitutes.

Alternatively, push a complete directory into the app sandbox and choose **Scan pushed directories**:

```sh
hdc file send -b com.example.gemma4mnn Qwen3-Reranker-0.6B-MNN /data/storage/el2/base/haps/entry/files/rerank-models/Qwen3-Reranker-0.6B-MNN
```

Select a model and load it. Changing categories or selecting another entry does not load or unload models. The loaded-model label shows which reranker is resident. Release it before changing the reranker or its runtime settings. The chat model can remain loaded if the device has sufficient memory.

## Request

Start the server on the API Service page. All endpoints share the same address and API key. Load a reranker before calling `/v1/rerank`; a chat model is not required.

`GET /v1/models` includes the loaded reranker's ID. The request's `model` field is optional; when supplied, it must match that ID.

```sh
curl http://DEVICE_IP:8080/v1/rerank \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"query":"What is the capital of China?","documents":["Beijing is the capital of China.","Shanghai lies at the mouth of the Yangtze River."],"top_n":2}'
```

Response structure, with illustrative scores:

```json
{
  "model": "loaded-model-id",
  "results": [
    { "index": 0, "relevance_score": 0.95 },
    { "index": 1, "relevance_score": 0.12 }
  ]
}
```

- `query` must be nonempty; `documents` contains 1–64 nonempty strings.
- `index` is the original zero-based position. Duplicate passages retain separate indices.
- `relevance_score` is the 0–1 score calculated by MNN Qwen3Reranker from yes/no logits. It measures query–passage relevance, not answer correctness.
- Results are sorted by descending score, with input order breaking ties. Optional `top_n` is an integer between 1 and the candidate count; omitting it returns all results.

## Limits and lifecycle

The per-item input limit includes the model template, query and one passage. It defaults to 2048 tokens and is configurable on the model page. Candidates are scored individually after all pass length validation. There is no silent truncation or partial-success response. The complete HTTP request is limited to 1 MiB.

The server returns 503 when no reranker is loaded, 400 for invalid or oversized input, 409 while model tasks are busy, and 500 for scoring failures. Requests are not queued; callers decide when to retry.

Disconnecting or stopping the server requests cancellation between candidate computations. The model remains protected until the native task finishes. API logs omit queries, candidate text and keys. Reranking does not write chat history.

Both builds expose the same endpoint. The experimental knowledge base does not automatically invoke reranking.
