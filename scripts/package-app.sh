#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/dist/QuietType.app"
ARM_BIN="$ROOT/.build/arm64-apple-macosx/debug/LocalTypeMac"
X86_BIN="$ROOT/.build/x86_64-apple-macosx/debug/LocalTypeMac"
SERVER_BIN="$ROOT/vendor/argmax-oss-swift/.build/arm64-apple-macosx/release/argmax-cli"
WHISPER_CPP_BIN="$ROOT/vendor/whisper.cpp/build-cpu/bin/whisper-cli"
SIGN_IDENTITY="${QUIETTYPE_CODESIGN_IDENTITY:--}"

if [[ -x "$ARM_BIN" ]]; then
  BIN="$ARM_BIN"
else
  BIN="$X86_BIN"
fi

if [[ ! -x "$BIN" ]]; then
  echo "Missing built binary: $BIN" >&2
  exit 1
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/resources/LocalTypeMac/Info.plist" "$APP/Contents/Info.plist"
cp "$BIN" "$APP/Contents/MacOS/LocalTypeMac"
if [[ -x "$SERVER_BIN" ]]; then
  cp "$SERVER_BIN" "$APP/Contents/MacOS/argmax-cli"
fi
if [[ -x "$WHISPER_CPP_BIN" ]]; then
  cp "$WHISPER_CPP_BIN" "$APP/Contents/MacOS/whisper-cli"
fi
cp "$ROOT/resources/QuietTypeIcon.svg" "$APP/Contents/Resources/QuietTypeIcon.svg"
if [[ -f "$ROOT/resources/QuietTypeIcon.icns" ]]; then
  cp "$ROOT/resources/QuietTypeIcon.icns" "$APP/Contents/Resources/QuietTypeIcon.icns"
fi
chmod +x "$APP/Contents/MacOS/LocalTypeMac"
if [[ -x "$APP/Contents/MacOS/argmax-cli" ]]; then
  chmod +x "$APP/Contents/MacOS/argmax-cli"
  codesign --force --sign "$SIGN_IDENTITY" "$APP/Contents/MacOS/argmax-cli" >/dev/null
fi
if [[ -x "$APP/Contents/MacOS/whisper-cli" ]]; then
  chmod +x "$APP/Contents/MacOS/whisper-cli"
  codesign --force --sign "$SIGN_IDENTITY" "$APP/Contents/MacOS/whisper-cli" >/dev/null
fi
codesign --force --sign "$SIGN_IDENTITY" "$APP/Contents/MacOS/LocalTypeMac" >/dev/null
codesign --force --sign "$SIGN_IDENTITY" "$APP" >/dev/null

echo "$APP"
