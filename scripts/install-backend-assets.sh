#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_SUPPORT="$HOME/Library/Application Support/QuietType"
GGML_MODELS="$APP_SUPPORT/Models"
WHISPERKIT_ROOT="$HOME/Documents/huggingface/models/argmaxinc/whisperkit-coreml"
WHISPERKIT_MODELS=(
  "openai_whisper-large-v3-v20240930_626MB"
  "openai_whisper-large-v3-v20240930_turbo"
)

download_file() {
  local url="$1"
  local output="$2"
  local label="$3"

  if [[ -s "$output" ]]; then
    printf 'FOUND %s %s\n' "$label" "$output"
    return
  fi

  mkdir -p "$(dirname "$output")"
  printf 'GET   %s\n' "$url"
  curl -L --fail --retry 3 --connect-timeout 20 "$url" -o "$output"
  printf 'WROTE %s %s\n' "$label" "$output"
}

install_whisperkit_tokenizers() {
  local tokenizer_url="https://huggingface.co/openai/whisper-large-v3/resolve/main/tokenizer.json"
  local tokenizer_config_url="https://huggingface.co/openai/whisper-large-v3/resolve/main/tokenizer_config.json"

  for model in "${WHISPERKIT_MODELS[@]}"; do
    local dir="$WHISPERKIT_ROOT/$model"
    if [[ ! -d "$dir" ]]; then
      printf 'SKIP  WhisperKit model dir missing: %s\n' "$dir"
      continue
    fi

    download_file "$tokenizer_url" "$dir/tokenizer.json" "$model tokenizer"
    download_file "$tokenizer_config_url" "$dir/tokenizer_config.json" "$model tokenizer config"
  done
}

install_ggml_models() {
  mkdir -p "$GGML_MODELS"
  download_file \
    "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en.bin" \
    "$GGML_MODELS/ggml-small.en.bin" \
    "whisper.cpp small.en"
}

print_backend_summary() {
  printf '\nQuietType backend summary\n'
  "$ROOT/scripts/check-asr.sh" || true

  printf '\nWhisperKit model completeness\n'
  for model in "${WHISPERKIT_MODELS[@]}"; do
    local dir="$WHISPERKIT_ROOT/$model"
    if [[ ! -d "$dir" ]]; then
      printf 'MISS  %s\n' "$dir"
      continue
    fi

    local missing=0
    for item in AudioEncoder.mlmodelc MelSpectrogram.mlmodelc TextDecoder.mlmodelc config.json generation_config.json tokenizer.json tokenizer_config.json; do
      if [[ ! -e "$dir/$item" ]]; then
        printf 'MISS  %s/%s\n' "$dir" "$item"
        missing=1
      fi
    done

    if [[ "$missing" -eq 0 ]]; then
      printf 'READY %s\n' "$dir"
    fi
  done
}

install_whisperkit_tokenizers
install_ggml_models
print_backend_summary
