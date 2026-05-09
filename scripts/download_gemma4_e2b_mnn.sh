#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODEL_ID="${MODEL_ID:-taobao-mnn/gemma-4-E2B-it-MNN}"
OUT_DIR="${1:-$ROOT_DIR/models/gemma-4-E2B-it-MNN}"

mkdir -p "$OUT_DIR"

if command -v huggingface-cli >/dev/null 2>&1; then
  huggingface-cli download "$MODEL_ID" --local-dir "$OUT_DIR"
  exit 0
fi

python3 - "$MODEL_ID" "$OUT_DIR" <<'PY'
import sys

try:
    from huggingface_hub import snapshot_download
except ImportError as exc:
    raise SystemExit(
        "huggingface_hub is required. Install it with: python3 -m pip install huggingface_hub"
    ) from exc

model_id, out_dir = sys.argv[1], sys.argv[2]
snapshot_download(repo_id=model_id, local_dir=out_dir, local_dir_use_symlinks=False)
PY
