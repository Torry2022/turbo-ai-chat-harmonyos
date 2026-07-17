#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MNN_ROOT="${MNN_ROOT:-$ROOT_DIR/.codex_mnn_source_3.6.0}"
BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/.codex_mnn_build_3.6.0}"
EXPECTED_COMMIT="cc20f672af9e177e2fa338c332dc097de2fc9264"
LIB_OUT="$ROOT_DIR/entry/src/main/libs/arm64-v8a"
INC_OUT="$ROOT_DIR/third_party/mnn/include"

actual_commit="$(git -C "$MNN_ROOT" rev-parse HEAD)"
[[ "$actual_commit" == "$EXPECTED_COMMIT" ]] || { echo "Unexpected MNN commit: $actual_commit" >&2; exit 1; }
[[ -f "$BUILD_DIR/libMNN.so" ]] || { echo "Missing $BUILD_DIR/libMNN.so" >&2; exit 1; }

mkdir -p "$LIB_OUT" "$INC_OUT/MNN" "$INC_OUT/llm"
cp "$BUILD_DIR/libMNN.so" "$LIB_OUT/libMNN.so"
rsync -a --delete "$MNN_ROOT/include/MNN/" "$INC_OUT/MNN/"
rsync -a --delete "$MNN_ROOT/transformers/llm/engine/include/llm/" "$INC_OUT/llm/"

sha256="$(sha256sum "$LIB_OUT/libMNN.so" | awk '{print $1}')"
cat > "$ROOT_DIR/third_party/mnn/BUILD_INFO.json" <<EOF
{
  "version": "3.6.0",
  "commit": "$EXPECTED_COMMIT",
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
    "opencv": true,
    "imageCodecs": true,
    "opencl": false
  },
  "libMnnSha256": "$sha256"
}
EOF
echo "Staged MNN 3.6.0 runtime and headers."
