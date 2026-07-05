#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODEL_REPO="${QUIETTYPE_WHISPERKIT_MODEL_REPO:-argmaxinc/whisperkit-coreml}"
MODEL_REVISION="${QUIETTYPE_WHISPERKIT_MODEL_REVISION:-97a5bf9bbc74c7d9c12c755d04dea59e672e3808}"
MODEL_NAME="${QUIETTYPE_WHISPERKIT_MODEL_NAME:-openai_whisper-large-v3-v20240930_626MB}"
MODEL_ROOT="${QUIETTYPE_MODEL_CACHE:-$ROOT/.model-cache/whisperkit-coreml}"
MODEL_DIR="$MODEL_ROOT/$MODEL_NAME"

if [[ -d "$MODEL_DIR" ]]; then
  echo "$MODEL_DIR"
  exit 0
fi

if ! python3 -c 'import huggingface_hub' >/dev/null 2>&1; then
  python3 -m pip install --user --quiet "huggingface_hub[hf_transfer]>=0.23"
fi

mkdir -p "$MODEL_ROOT"
export HF_HUB_ENABLE_HF_TRANSFER="${HF_HUB_ENABLE_HF_TRANSFER:-1}"

python3 - "$MODEL_REPO" "$MODEL_REVISION" "$MODEL_NAME" "$MODEL_ROOT" <<'PY'
import sys
from huggingface_hub import snapshot_download

repo_id, revision, model_name, local_dir = sys.argv[1:]
snapshot_download(
    repo_id=repo_id,
    revision=revision,
    local_dir=local_dir,
    allow_patterns=[f"{model_name}/**"],
)
PY

for item in AudioEncoder.mlmodelc MelSpectrogram.mlmodelc TextDecoder.mlmodelc config.json generation_config.json tokenizer.json tokenizer_config.json; do
  if [[ ! -e "$MODEL_DIR/$item" ]]; then
    echo "Missing WhisperKit model item: $MODEL_DIR/$item" >&2
    exit 1
  fi
done

echo "$MODEL_DIR"
