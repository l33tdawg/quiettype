#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

found_command=0
found_model=0

print_header() {
  printf '\n%s\n' "$1"
}

check_command_name() {
  local name="$1"
  local resolved

  if resolved="$(command -v "$name" 2>/dev/null)"; then
    printf 'FOUND command %-12s %s\n' "$name" "$resolved"
    found_command=1
  else
    printf 'MISS  command %-12s not found in PATH\n' "$name"
  fi
}

check_executable_path() {
  local path="$1"

  if [[ -x "$path" ]]; then
    printf 'FOUND executable %s\n' "$path"
    found_command=1
  elif [[ -e "$path" ]]; then
    printf 'MISS  executable %s exists but is not executable\n' "$path"
  else
    printf 'MISS  executable %s\n' "$path"
  fi
}

check_model_file() {
  local path="$1"

  if [[ -f "$path" ]]; then
    printf 'FOUND model %s\n' "$path"
    found_model=1
  else
    printf 'MISS  model %s\n' "$path"
  fi
}

check_model_dir() {
  local dir="$1"

  if [[ ! -d "$dir" ]]; then
    printf 'MISS  model-dir %s\n' "$dir"
    return
  fi

  printf 'FOUND model-dir %s\n' "$dir"

  shopt -s nullglob
  local models=("$dir"/ggml-*.bin "$dir"/*.mlmodelc "$dir"/*.mlpackage)
  shopt -u nullglob

  if (( ${#models[@]} == 0 )); then
    printf 'MISS  model-files in %s\n' "$dir"
    return
  fi

  local model
  for model in "${models[@]}"; do
    if [[ -f "$model" || -d "$model" ]]; then
      printf 'FOUND model %s\n' "$model"
      found_model=1
    fi
  done
}

print_header "QuietType local ASR check"
printf 'Repo: %s\n' "$ROOT"
printf 'Network: not used\n'

if command -v uname >/dev/null 2>&1; then
  printf 'System: %s\n' "$(uname -sm)"
fi

if command -v sysctl >/dev/null 2>&1; then
  chip="$(sysctl -n machdep.cpu.brand_string 2>/dev/null || true)"
  if [[ -n "${chip:-}" ]]; then
    printf 'CPU: %s\n' "$chip"
  fi
fi

print_header "Supported ASR commands in PATH"
check_command_name "whisper-cli"
check_command_name "main"
check_command_name "whisper"

print_header "Common local executable paths"
check_executable_path "/opt/homebrew/bin/whisper-cli"
check_executable_path "/opt/homebrew/bin/whisper"
check_executable_path "/usr/local/bin/whisper-cli"
check_executable_path "/usr/local/bin/whisper"
check_executable_path "$HOME/whisper.cpp/build/bin/whisper-cli"
check_executable_path "$HOME/whisper.cpp/main"
check_executable_path "$ROOT/dist/QuietType.app/Contents/MacOS/whisper-cli"
check_executable_path "$ROOT/vendor/whisper.cpp/build-cpu/bin/whisper-cli"
check_executable_path "$ROOT/vendor/whisper.cpp/build/bin/whisper-cli"
check_executable_path "$ROOT/third_party/whisper.cpp/build/bin/whisper-cli"
check_executable_path "$ROOT/build/bin/whisper-cli"

print_header "Common whisper.cpp model files"
check_model_file "$ROOT/models/ggml-tiny.en.bin"
check_model_file "$ROOT/models/ggml-base.en.bin"
check_model_file "$ROOT/models/ggml-small.en.bin"
check_model_file "$ROOT/models/ggml-large-v3-turbo.bin"
check_model_file "$ROOT/resources/Models/ggml-tiny.en.bin"
check_model_file "$ROOT/resources/Models/ggml-base.en.bin"
check_model_file "$ROOT/resources/Models/ggml-small.en.bin"
check_model_file "$ROOT/resources/Models/ggml-large-v3-turbo.bin"
check_model_file "$HOME/Library/Application Support/QuietType/Models/ggml-tiny.en.bin"
check_model_file "$HOME/Library/Application Support/QuietType/Models/ggml-base.en.bin"
check_model_file "$HOME/Library/Application Support/QuietType/Models/ggml-small.en.bin"
check_model_file "$HOME/Library/Application Support/QuietType/Models/ggml-large-v3-turbo.bin"
check_model_file "$HOME/.cache/whisper.cpp/ggml-tiny.en.bin"
check_model_file "$HOME/.cache/whisper.cpp/ggml-base.en.bin"
check_model_file "$HOME/.cache/whisper.cpp/ggml-small.en.bin"
check_model_file "$HOME/.cache/whisper.cpp/ggml-large-v3-turbo.bin"
check_model_file "$HOME/whisper.cpp/models/ggml-tiny.en.bin"
check_model_file "$HOME/whisper.cpp/models/ggml-base.en.bin"
check_model_file "$HOME/whisper.cpp/models/ggml-small.en.bin"
check_model_file "$HOME/whisper.cpp/models/ggml-large-v3-turbo.bin"

print_header "Model directories"
check_model_dir "$ROOT/models"
check_model_dir "$ROOT/resources/Models"
check_model_dir "$HOME/Library/Application Support/QuietType/Models"
check_model_dir "$HOME/.cache/whisper.cpp"
check_model_dir "$HOME/whisper.cpp/models"

print_header "Summary"
if (( found_command == 1 )); then
  printf 'ASR command: found\n'
else
  printf 'ASR command: missing\n'
fi

if (( found_model == 1 )); then
  printf 'ASR model: found\n'
else
  printf 'ASR model: missing\n'
fi

if (( found_command == 1 && found_model == 1 )); then
  printf 'Ready: yes, a command backend has the minimum local pieces.\n'
  exit 0
fi

printf 'Ready: no, install or point QuietType at a local command and model.\n'
exit 1
