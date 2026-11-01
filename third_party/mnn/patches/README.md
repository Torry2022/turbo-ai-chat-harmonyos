# MNN compatibility patches

Base: `f0b6105c5c7f901b1531dd4c23afa8a00b454db3`.

- `0003-tokenizer-nfc.patch` implements the tokenizer pipeline's NFC normalizer
  with utf8proc. The bundled sources and license are in `../utf8proc/`; the build
  scripts copy them into the MNN checkout before applying the patches.
- `0004-streaming-added-token.patch` makes single-token streaming decode look up
  added tokens before the base vocabulary. It preserves the literal text of
  tokens absent from the base vocabulary, including model-defined tool markers.
  Batch decoding and stop-token handling are unchanged.

- `0005-reranker-load-validation.patch` checks model loading and yes/no token IDs
  before scoring. This header-only change is compiled into the app bridge; it
  does not replace the staged MNN binary.

- `0007-cpu-runtime-width.patch` reads the existing LLM executor's CPU runtime
  width without creating another backend. The app checks it at load completion
  and exposes requested threads and actual maximum CPU width separately.

- `0008-refresh-generation-sampler.patch` refreshes sampler settings at each
  generation boundary while preserving its random-number generator state.

Thread-pool capacity and zero-temperature policy are handled by the app using
existing MNN interfaces. The app prepares capacity before loading a model, with
each runtime retaining its requested width. It translates zero temperature to
penalty filtering followed by greedy selection. Neither changes MNN's pool or
sampling policy. Capacity initialization retains idle workers until process exit.

The previous Omni attention-mask and PLE patches are no longer applied: this
baseline dispatches generation masks correctly and rebuilds text PLE embeddings.
The build keeps `MNN_BUILD_LLM_OMNI=ON` for multimodal models.
