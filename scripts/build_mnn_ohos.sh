#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MNN_ROOT="${MNN_ROOT:-$ROOT_DIR/../MNN}"
BUILD_DIR="${BUILD_DIR:-$MNN_ROOT/project/harmony/build_gemma4_min}"
JOBS="${JOBS:-$(sysctl -n hw.ncpu 2>/dev/null || echo 4)}"

find_harmony_home() {
  if [[ -n "${HARMONY_HOME:-}" ]]; then
    if [[ -f "$HARMONY_HOME/build/cmake/ohos.toolchain.cmake" ]]; then
      echo "$HARMONY_HOME"
      return 0
    fi
    if [[ -f "$HARMONY_HOME/native/build/cmake/ohos.toolchain.cmake" ]]; then
      echo "$HARMONY_HOME/native"
      return 0
    fi
  fi

  local sdk_roots=(
    "$HOME/Library/OpenHarmony/Sdk"
    "$HOME/Library/HarmonyOS/Sdk"
    "$HOME/Library/Huawei/Sdk"
    "/Applications/DevEco-Studio.app/Contents/sdk"
    "/Applications/DevEco Studio.app/Contents/sdk"
    "$HOME/Applications/DevEco-Studio.app/Contents/sdk"
    "$HOME/Applications/DevEco Studio.app/Contents/sdk"
  )

  for base in "${sdk_roots[@]}"; do
    if [[ -d "$base" ]]; then
      local found
      found="$(find "$base" -maxdepth 7 -path '*/native/build/cmake/ohos.toolchain.cmake' -print 2>/dev/null | sort -r | head -1)"
      if [[ -n "$found" ]]; then
        dirname "$(dirname "$(dirname "$found")")"
        return 0
      fi
    fi
  done

  return 1
}

HARMONY_NATIVE_HOME="$(find_harmony_home || true)"
if [[ -z "$HARMONY_NATIVE_HOME" ]]; then
  echo "Cannot find Harmony/OpenHarmony native SDK. Set HARMONY_HOME to the SDK native directory." >&2
  exit 1
fi

cmake -S "$MNN_ROOT" -B "$BUILD_DIR" \
  -DCMAKE_TOOLCHAIN_FILE="$HARMONY_NATIVE_HOME/build/cmake/ohos.toolchain.cmake" \
  -DCMAKE_BUILD_TYPE=Release \
  -DOHOS_ARCH=arm64-v8a \
  -DOHOS_STL=c++_static \
  -DOHOS_PLATFORM_LEVEL=9 \
  -DMNN_BUILD_LLM=ON \
  -DMNN_BUILD_LLM_OMNI=ON \
  -DMNN_LOW_MEMORY=ON \
  -DMNN_SUPPORT_TRANSFORMER_FUSE=ON \
  -DMNN_CPU_WEIGHT_DEQUANT_GEMM=ON \
  -DMNN_ARM82=ON \
  -DMNN_USE_LOGCAT=ON \
  -DMNN_BUILD_TEST=OFF \
  -DMNN_BUILD_BENCHMARK=OFF \
  -DLLM_SUPPORT_VISION=ON \
  -DMNN_BUILD_AUDIO=OFF \
  -DMNN_BUILD_OPENCV=ON \
  -DMNN_IMGCODECS=ON \
  -DMNN_BUILD_DIFFUSION=OFF \
  -DMNN_OPENCL="${MNN_OPENCL:-OFF}" \
  -DMNN_SEP_BUILD=OFF \
  -DNATIVE_LIBRARY_OUTPUT=. \
  -DNATIVE_INCLUDE_OUTPUT=.

cmake --build "$BUILD_DIR" --target MNN -j "$JOBS"

echo "$BUILD_DIR"
