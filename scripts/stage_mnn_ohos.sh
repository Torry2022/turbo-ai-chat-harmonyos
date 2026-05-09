#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MNN_ROOT="${MNN_ROOT:-$ROOT_DIR/../MNN}"
BUILD_DIR="${BUILD_DIR:-$MNN_ROOT/project/harmony/build_gemma4_min}"
LIB_OUT="$ROOT_DIR/entry/src/main/libs/arm64-v8a"
INC_OUT="$ROOT_DIR/third_party/mnn/include"

if [[ ! -f "$BUILD_DIR/libMNN.so" ]]; then
  echo "Missing $BUILD_DIR/libMNN.so. Run scripts/build_mnn_ohos.sh first." >&2
  exit 1
fi

mkdir -p "$LIB_OUT" "$INC_OUT/MNN" "$INC_OUT/llm"
cp "$BUILD_DIR/libMNN.so" "$LIB_OUT/libMNN.so"
rsync -a --delete "$MNN_ROOT/include/MNN/" "$INC_OUT/MNN/"
rsync -a --delete "$MNN_ROOT/transformers/llm/engine/include/llm/" "$INC_OUT/llm/"

echo "Staged libMNN.so and headers into $ROOT_DIR"
