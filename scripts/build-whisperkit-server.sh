#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR="$ROOT/vendor/argmax-oss-swift"
PATCH="$ROOT/patches/argmax-whisperkit-prefill-guard.patch"
EXPECTED_REVISION="${QUIETTYPE_ARGMAX_REVISION:-dcf3a00f0ae4d5b57bc0aad92063b102b70d5fd1}"

if [[ ! -d "$VENDOR" ]]; then
  echo "Missing $VENDOR. Run:" >&2
  echo "  git clone https://github.com/argmaxinc/argmax-oss-swift.git vendor/argmax-oss-swift" >&2
  exit 1
fi

if [[ ! -f "$PATCH" ]]; then
  echo "Missing required Argmax compatibility patch: $PATCH" >&2
  exit 1
fi

ACTUAL_REVISION="$(git -C "$VENDOR" rev-parse HEAD)"
if [[ "$ACTUAL_REVISION" != "$EXPECTED_REVISION" ]]; then
  echo "Unexpected Argmax revision '$ACTUAL_REVISION'; expected '$EXPECTED_REVISION'." >&2
  exit 1
fi

if git -C "$VENDOR" apply --check "$PATCH" >/dev/null 2>&1; then
  git -C "$VENDOR" apply "$PATCH"
  echo "Applied QuietType Argmax prefill guard."
elif git -C "$VENDOR" apply --reverse --check "$PATCH" >/dev/null 2>&1; then
  echo "QuietType Argmax prefill guard is already applied."
else
  echo "Argmax prefill guard does not apply cleanly at $ACTUAL_REVISION." >&2
  exit 1
fi

cd "$VENDOR"
BUILD_ALL=1 \
SWIFTPM_HOME="$ROOT/.swiftpm-home" \
CLANG_MODULE_CACHE_PATH="$ROOT/.clang-module-cache" \
swift build -c release --product argmax-cli --arch arm64

echo "$VENDOR/.build/arm64-apple-macosx/release/argmax-cli"
