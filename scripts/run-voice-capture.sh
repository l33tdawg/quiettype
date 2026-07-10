#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/.build/QuietType Voice Capture.app"
OPEN_APP=1

if [[ "${1:-}" == "--no-open" ]]; then
  OPEN_APP=0
  shift
fi

if [[ $# -ne 0 ]]; then
  echo "Usage: scripts/run-voice-capture.sh [--no-open]" >&2
  exit 2
fi

export SWIFTPM_HOME="${SWIFTPM_HOME:-$ROOT/.swiftpm-home}"
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$ROOT/.clang-module-cache}"

arch -arm64 swift build \
  --package-path "$ROOT" \
  --arch arm64 \
  --product LocalTypeVoiceCapture

BIN_DIR="$(arch -arm64 swift build --package-path "$ROOT" --arch arm64 --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"
cp "$ROOT/resources/LocalTypeVoiceCapture/Info.plist" "$APP/Contents/Info.plist"
cp "$BIN_DIR/LocalTypeVoiceCapture" "$APP/Contents/MacOS/LocalTypeVoiceCapture"
chmod 755 "$APP/Contents/MacOS/LocalTypeVoiceCapture"
codesign --force --deep --sign - "$APP"

echo "Packaged $APP"
if [[ "$OPEN_APP" == "1" ]]; then
  open "$APP"
fi
