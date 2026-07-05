#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/dist/QuietType.app"
ARM_RELEASE_BIN="$ROOT/.build/arm64-apple-macosx/release/LocalTypeMac"
ARM_BIN="$ROOT/.build/arm64-apple-macosx/debug/LocalTypeMac"
X86_RELEASE_BIN="$ROOT/.build/x86_64-apple-macosx/release/LocalTypeMac"
X86_BIN="$ROOT/.build/x86_64-apple-macosx/debug/LocalTypeMac"
SERVER_BIN="$ROOT/vendor/argmax-oss-swift/.build/arm64-apple-macosx/release/argmax-cli"
WHISPER_CPP_BIN="$ROOT/vendor/whisper.cpp/build-cpu/bin/whisper-cli"
DEFAULT_WHISPERKIT_MODEL="$HOME/Documents/huggingface/models/argmaxinc/whisperkit-coreml/openai_whisper-large-v3-v20240930_626MB"
DEFAULT_SAGE_APP="$ROOT/vendor/SAGE.app"
SIGN_IDENTITY="${QUIETTYPE_CODESIGN_IDENTITY:--}"
SIGN_OPTIONS="${QUIETTYPE_CODESIGN_OPTIONS:---options runtime}"
ENTITLEMENTS="${QUIETTYPE_ENTITLEMENTS:-$ROOT/resources/LocalTypeMac/QuietType.entitlements}"
BUNDLE_MODELS="${QUIETTYPE_BUNDLE_MODELS:-1}"
BUNDLE_SAGE="${QUIETTYPE_BUNDLE_SAGE:-1}"
WHISPERKIT_MODEL_SOURCE="${QUIETTYPE_WHISPERKIT_MODEL_SOURCE:-$DEFAULT_WHISPERKIT_MODEL}"
SAGE_APP_SOURCE="${QUIETTYPE_SAGE_APP_SOURCE:-$DEFAULT_SAGE_APP}"
APP_VERSION="${QUIETTYPE_VERSION:-}"
APP_BUILD="${QUIETTYPE_BUILD:-}"

require_sage_app() {
  local sage_app="$1"
  local executable="$sage_app/Contents/MacOS/sage-gui"

  if [[ ! -d "$sage_app" ]]; then
    echo "Missing SAGE app bundle: $sage_app" >&2
    exit 1
  fi

  if [[ ! -x "$executable" ]]; then
    echo "Bundled SAGE app is not runnable; missing executable: $executable" >&2
    exit 1
  fi
}

if [[ -x "$ARM_RELEASE_BIN" ]]; then
  BIN="$ARM_RELEASE_BIN"
elif [[ -x "$ARM_BIN" ]]; then
  BIN="$ARM_BIN"
elif [[ -x "$X86_RELEASE_BIN" ]]; then
  BIN="$X86_RELEASE_BIN"
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
if [[ -n "$APP_VERSION" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APP_VERSION" "$APP/Contents/Info.plist"
fi
if [[ -n "$APP_BUILD" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $APP_BUILD" "$APP/Contents/Info.plist"
fi
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")"
if [[ "$BUNDLE_ID" != "local.quiettype.mac" ]]; then
  echo "Unexpected bundle identifier '$BUNDLE_ID'; refusing to package because this would reset macOS permissions." >&2
  exit 1
fi
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
if [[ "$BUNDLE_MODELS" != "0" && "$BUNDLE_MODELS" != "false" ]]; then
  if [[ -d "$WHISPERKIT_MODEL_SOURCE" ]]; then
    mkdir -p "$APP/Contents/Resources/WhisperKit"
    cp -R "$WHISPERKIT_MODEL_SOURCE" "$APP/Contents/Resources/WhisperKit/"
  else
    echo "WARN  WhisperKit model not bundled; missing $WHISPERKIT_MODEL_SOURCE" >&2
  fi
fi
if [[ "$BUNDLE_SAGE" != "0" && "$BUNDLE_SAGE" != "false" ]]; then
  if [[ -d "$SAGE_APP_SOURCE" ]]; then
    require_sage_app "$SAGE_APP_SOURCE"
    cp -R "$SAGE_APP_SOURCE" "$APP/Contents/Resources/SAGE.app"
    require_sage_app "$APP/Contents/Resources/SAGE.app"
  else
    echo "SAGE GUI is required for release packaging but was not found at $SAGE_APP_SOURCE" >&2
    exit 1
  fi
fi
MAIN_ENTITLEMENTS_OPTIONS=()
if [[ -f "$ENTITLEMENTS" ]]; then
  MAIN_ENTITLEMENTS_OPTIONS=(--entitlements "$ENTITLEMENTS")
else
  echo "Entitlements file is required for release packaging but was not found: $ENTITLEMENTS" >&2
  exit 1
fi
chmod +x "$APP/Contents/MacOS/LocalTypeMac"
if [[ -x "$APP/Contents/MacOS/argmax-cli" ]]; then
  chmod +x "$APP/Contents/MacOS/argmax-cli"
  codesign --force --sign "$SIGN_IDENTITY" $SIGN_OPTIONS "$APP/Contents/MacOS/argmax-cli" >/dev/null
fi
if [[ -x "$APP/Contents/MacOS/whisper-cli" ]]; then
  chmod +x "$APP/Contents/MacOS/whisper-cli"
  codesign --force --sign "$SIGN_IDENTITY" $SIGN_OPTIONS "$APP/Contents/MacOS/whisper-cli" >/dev/null
fi
if [[ -d "$APP/Contents/Resources/SAGE.app" ]]; then
  codesign --force --deep --sign "$SIGN_IDENTITY" $SIGN_OPTIONS "$APP/Contents/Resources/SAGE.app" >/dev/null
fi
codesign --force --sign "$SIGN_IDENTITY" $SIGN_OPTIONS "${MAIN_ENTITLEMENTS_OPTIONS[@]}" "$APP/Contents/MacOS/LocalTypeMac" >/dev/null
codesign --force --sign "$SIGN_IDENTITY" $SIGN_OPTIONS "${MAIN_ENTITLEMENTS_OPTIONS[@]}" "$APP" >/dev/null

echo "$APP"
