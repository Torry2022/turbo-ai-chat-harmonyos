# Local MNN patches

Base: `2edeef91b425e98a93707840b6fffdd97980bdbe`.

`0001-omni-generation-attention-mask.patch` restores the generation attention-mask
path in `Omni`. After `Omni` began inheriting from `Embedding`, it inherited the
embedding mask implementation as well. For a CPU Gemma 4 model with
`attention_type=mix`, this supplied a scalar instead of the five-dimensional
full/sliding mask required by the exported graph. The first Gather operation on
that mask failed before any token was generated.

The override delegates to `Llm` for generation and retains `Embedding` behavior
when `is_embedding=true`. It does not change model files or identify models by
name. The build scripts apply the patch idempotently; staging records its SHA-256
in `BUILD_INFO.json` and requires the patch to be present in the source checkout.

Device regression: on MatePad Edge, the same Gemma E4B files passed text and image
generation with MNN 3.6.0, failed both with the unpatched snapshot, and passed both
with this patch. Embedding-mode execution has not been device-tested.

`0002-omni-text-prefill-ple.patch` clears stale PLE input before a text-only
prefill in `Omni`. The snapshot routes text-only requests directly to
`Llm::embedding`, which preserves non-null PLE for multi-token inputs to avoid
overwriting the full PLE prepared by multimodal processing. After decoding a
previous response, however, that value contains only the last token's PLE.
On MatePad Edge, a new 109-token prompt was observed entering this path with
a cached PLE sequence length of 1. Successive requests then produced unrelated
or repetitive output even after resetting the conversation.

The patch invalidates PLE only for multi-token text-only input; image/audio
prefill retains its own full-sequence PLE. It does not change weights, templates,
sampling settings, or models without PLE. Both patches are required by the
build/staging scripts and recorded separately in `BUILD_INFO.json`.

With the second patch, Gemma E2B completed five successive fresh text requests
normally on MatePad Edge (16–29 tokens each); before it, the same App source and
snapshot produced a normal first response followed by four unrelated/repetitive
responses reaching 512 tokens. A two-turn recall check and two image-to-text
switches also completed normally. This is a targeted regression check, not a
general model-quality benchmark; one image response still omitted the banana.
