#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODEL_ID="${MODEL_ID:-MNN/Qwen3-4B-Instruct-2507-MNN}"
OUT_DIR="${1:-$ROOT_DIR/models/Qwen3-4B-Instruct-2507-MNN}"

mkdir -p "$OUT_DIR"

if command -v modelscope >/dev/null 2>&1; then
  modelscope download --model "$MODEL_ID" --local_dir "$OUT_DIR"
  exit 0
fi

python3 - "$MODEL_ID" "$OUT_DIR" <<'PY'
import sys

try:
    from modelscope import snapshot_download
except ImportError as exc:
    raise SystemExit(
        "modelscope is required. Install it with: python3 -m pip install modelscope"
    ) from exc

model_id, out_dir = sys.argv[1], sys.argv[2]
snapshot_download(model_id, local_dir=out_dir)
PY
