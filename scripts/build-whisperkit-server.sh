#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR="$ROOT/vendor/argmax-oss-swift"

if [[ ! -d "$VENDOR" ]]; then
  echo "Missing $VENDOR. Run:" >&2
  echo "  git clone https://github.com/argmaxinc/argmax-oss-swift.git vendor/argmax-oss-swift" >&2
  exit 1
fi

cd "$VENDOR"
BUILD_ALL=1 \
SWIFTPM_HOME="$ROOT/.swiftpm-home" \
CLANG_MODULE_CACHE_PATH="$ROOT/.clang-module-cache" \
swift build -c release --product argmax-cli --arch arm64

echo "$VENDOR/.build/arm64-apple-macosx/release/argmax-cli"
