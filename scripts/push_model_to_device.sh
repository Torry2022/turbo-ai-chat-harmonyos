#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODEL_DIR="${1:-$ROOT_DIR/models/gemma-4-E2B-it-MNN}"
BUNDLE="${BUNDLE:-com.example.gemma4mnn}"
USER_ID="${USER_ID:-100}"
DEVICE_FILES_DIR="${DEVICE_FILES_DIR:-/data/app/el2/$USER_ID/base/$BUNDLE/haps/entry/files}"

if [[ ! -d "$MODEL_DIR" ]]; then
  echo "Missing model directory: $MODEL_DIR" >&2
  echo "Run scripts/download_gemma4_e2b_mnn.sh first." >&2
  exit 1
fi

if ! command -v hdc >/dev/null 2>&1; then
  echo "hdc is not in PATH. Source your Harmony environment first." >&2
  exit 1
fi

TARGET_ARG=()
if [[ -n "${HDC_TARGET:-}" ]]; then
  TARGET_ARG=(-t "$HDC_TARGET")
fi

if ! hdc "${TARGET_ARG[@]}" list targets | grep -q .; then
  echo "No Harmony device found. Connect and unlock a device, then retry." >&2
  exit 1
fi

MODEL_NAME="$(basename "$MODEL_DIR")"
hdc "${TARGET_ARG[@]}" shell "mkdir -p '$DEVICE_FILES_DIR'"
hdc "${TARGET_ARG[@]}" file send "$MODEL_DIR" "$DEVICE_FILES_DIR/"

cat <<EOF
Model copied to device.

App-visible config path:
  /data/storage/el2/base/haps/entry/files/$MODEL_NAME/config.json

Physical device path used by this script:
  $DEVICE_FILES_DIR/$MODEL_NAME/config.json
EOF
