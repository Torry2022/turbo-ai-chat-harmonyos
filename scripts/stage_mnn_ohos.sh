#!/usr/bin/env bash
# Derived from Turbo1123/turbo-ai-chat-harmonyos and subsequently modified.
# See README.md and Git history for provenance and change details.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MNN_ROOT="${MNN_ROOT:-$ROOT_DIR/.codex_mnn_source_2edeef91}"
BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/.codex_mnn_build_2edeef91}"
EXPECTED_COMMIT="2edeef91b425e98a93707840b6fffdd97980bdbe"
LIB_OUT="$ROOT_DIR/entry/src/main/libs/arm64-v8a"
INC_OUT="$ROOT_DIR/third_party/mnn/include"

actual_commit="$(git -C "$MNN_ROOT" rev-parse HEAD)"
[[ "$actual_commit" == "$EXPECTED_COMMIT" ]] || { echo "Unexpected MNN commit: $actual_commit" >&2; exit 1; }
[[ -f "$BUILD_DIR/libMNN.so" ]] || { echo "Missing $BUILD_DIR/libMNN.so" >&2; exit 1; }
for patch_name in 0001-omni-generation-attention-mask.patch 0002-omni-text-prefill-ple.patch; do
  git -C "$MNN_ROOT" apply --reverse --check "$ROOT_DIR/third_party/mnn/patches/$patch_name"
done

mkdir -p "$LIB_OUT" "$INC_OUT/MNN" "$INC_OUT/llm"
cp "$BUILD_DIR/libMNN.so" "$LIB_OUT/libMNN.so"
rsync -a --delete "$MNN_ROOT/include/MNN/" "$INC_OUT/MNN/"
rsync -a --delete "$MNN_ROOT/transformers/llm/engine/include/llm/" "$INC_OUT/llm/"

sha256="$(sha256sum "$LIB_OUT/libMNN.so" | awk '{print $1}')"
cat > "$ROOT_DIR/third_party/mnn/BUILD_INFO.json" <<EOF
{
  "version": "3.6.1-dev+2edeef91",
  "commit": "$EXPECTED_COMMIT",
  "patches": [
    {"file": "patches/0001-omni-generation-attention-mask.patch", "sha256": "$(sha256sum "$ROOT_DIR/third_party/mnn/patches/0001-omni-generation-attention-mask.patch" | awk '{print $1}')"},
    {"file": "patches/0002-omni-text-prefill-ple.patch", "sha256": "$(sha256sum "$ROOT_DIR/third_party/mnn/patches/0002-omni-text-prefill-ple.patch" | awk '{print $1}')"}
  ],
  "architecture": "arm64-v8a",
  "stl": "c++_shared",
  "ohosPlatformLevel": 9,
  "features": {
    "sharedLibraries": true,
    "llm": true,
    "llmOmni": true,
    "lowMemory": true,
    "transformerFuse": true,
    "arm82": true,
    "sme2": false,
    "opencv": true,
    "imageCodecs": true,
    "opencl": false
  },
  "libMnnSha256": "$sha256"
}
EOF
echo "Staged MNN development snapshot 2edeef91 runtime and headers."
