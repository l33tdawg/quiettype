#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR="$ROOT/vendor/argmax-oss-swift"
PREFILL_PATCH="$ROOT/patches/argmax-whisperkit-prefill-guard.patch"
LIVE_PCM_PATCH="$ROOT/patches/argmax-live-pcm-stream.patch"
EXPECTED_REVISION="${QUIETTYPE_ARGMAX_REVISION:-dcf3a00f0ae4d5b57bc0aad92063b102b70d5fd1}"

if [[ ! -d "$VENDOR" ]]; then
  echo "Missing $VENDOR. Run:" >&2
  echo "  git clone https://github.com/argmaxinc/argmax-oss-swift.git vendor/argmax-oss-swift" >&2
  exit 1
fi

for patch in "$PREFILL_PATCH" "$LIVE_PCM_PATCH"; do
  if [[ ! -f "$patch" ]]; then
    echo "Missing required Argmax compatibility patch: $patch" >&2
    exit 1
  fi
done

ACTUAL_REVISION="$(git -C "$VENDOR" rev-parse HEAD)"
if [[ "$ACTUAL_REVISION" != "$EXPECTED_REVISION" ]]; then
  echo "Unexpected Argmax revision '$ACTUAL_REVISION'; expected '$EXPECTED_REVISION'." >&2
  exit 1
fi

apply_patch_once() {
  local patch="$1"
  local label="$2"
  if git -C "$VENDOR" apply --unidiff-zero --reverse --check "$patch" >/dev/null 2>&1; then
    echo "QuietType $label is already applied."
  elif git -C "$VENDOR" apply --unidiff-zero --check "$patch" >/dev/null 2>&1; then
    git -C "$VENDOR" apply --unidiff-zero "$patch"
    echo "Applied QuietType $label."
  else
    echo "Argmax $label does not apply cleanly at $ACTUAL_REVISION." >&2
    exit 1
  fi
}

apply_patch_once "$PREFILL_PATCH" "prefill guard"
apply_patch_once "$LIVE_PCM_PATCH" "live PCM stream"

cd "$VENDOR"
BUILD_ALL=1 \
SWIFTPM_HOME="$ROOT/.swiftpm-home" \
CLANG_MODULE_CACHE_PATH="$ROOT/.clang-module-cache" \
swift build -c release --product argmax-cli --arch arm64

echo "$VENDOR/.build/arm64-apple-macosx/release/argmax-cli"
