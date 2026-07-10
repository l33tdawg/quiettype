#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

export SWIFTPM_HOME="${SWIFTPM_HOME:-$ROOT/.swiftpm-home}"
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$ROOT/.clang-module-cache}"

exec arch -arm64 swift run \
  --package-path "$ROOT" \
  localtype-voice-benchmark \
  "$@"
