#!/usr/bin/env bash
# Derived from Turbo1123/turbo-ai-chat-harmonyos and subsequently modified.
# See README.md and Git history for provenance and change details.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MNN_ROOT="${MNN_ROOT:-$ROOT_DIR/.codex_mnn_source_3.6.0}"
BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/.codex_mnn_build_3.6.0}"
EXPECTED_COMMIT="cc20f672af9e177e2fa338c332dc097de2fc9264"
JOBS="${JOBS:-4}"

find_native_home() {
  local candidate="${HARMONY_NATIVE_HOME:-${HARMONY_HOME:-}}"
  if [[ -n "$candidate" && -f "$candidate/build/cmake/ohos.toolchain.cmake" ]]; then
    printf '%s\n' "$candidate"
    return
  fi
  if [[ -n "$candidate" && -f "$candidate/native/build/cmake/ohos.toolchain.cmake" ]]; then
    printf '%s\n' "$candidate/native"
    return
  fi
  echo "Set HARMONY_NATIVE_HOME to the HarmonyOS native SDK directory." >&2
  exit 1
}

if [[ ! -d "$MNN_ROOT/.git" ]]; then
  echo "Missing MNN source checkout: $MNN_ROOT" >&2
  echo "Clone tag 3.6.0 before building." >&2
  exit 1
fi

actual_commit="$(git -C "$MNN_ROOT" rev-parse HEAD)"
if [[ "$actual_commit" != "$EXPECTED_COMMIT" ]]; then
  echo "Expected MNN $EXPECTED_COMMIT, found $actual_commit" >&2
  exit 1
fi

native_home="$(find_native_home)"
cmake -S "$MNN_ROOT" -B "$BUILD_DIR" -G Ninja \
  -DCMAKE_TOOLCHAIN_FILE="$native_home/build/cmake/ohos.toolchain.cmake" \
  -DCMAKE_BUILD_TYPE=Release \
  -DOHOS_ARCH=arm64-v8a \
  -DOHOS_STL=c++_shared \
  -DOHOS_PLATFORM_LEVEL=9 \
  -DMNN_BUILD_SHARED_LIBS=ON \
  -DMNN_BUILD_LLM=ON \
  -DMNN_BUILD_LLM_OMNI=ON \
  -DMNN_LOW_MEMORY=ON \
  -DMNN_SUPPORT_TRANSFORMER_FUSE=ON \
  -DMNN_ARM82=ON \
  -DMNN_USE_LOGCAT=ON \
  -DMNN_BUILD_TEST=OFF \
  -DMNN_BUILD_BENCHMARK=OFF \
  -DMNN_BUILD_AUDIO=OFF \
  -DMNN_BUILD_OPENCV=ON \
  -DMNN_IMGCODECS=ON \
  -DMNN_BUILD_DIFFUSION=OFF \
  -DMNN_OPENCL=OFF \
  -DMNN_SEP_BUILD=OFF \
  -DMNN_USE_SSE=OFF

cmake --build "$BUILD_DIR" --target MNN -j "$JOBS"
echo "$BUILD_DIR/libMNN.so"
