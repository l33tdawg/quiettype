#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SWIFTPM_HOME="${SWIFTPM_HOME:-$ROOT/.swiftpm-home}"
CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$ROOT/.clang-module-cache}"
SIGN_IDENTITY="${QUIETTYPE_CODESIGN_IDENTITY:-Developer ID Application: Dhillon Kannabhiran (2N7GKZ8D8Z)}"
NOTARIZE="${QUIETTYPE_NOTARIZE:-0}"

export SWIFTPM_HOME
export CLANG_MODULE_CACHE_PATH
export QUIETTYPE_CODESIGN_IDENTITY="$SIGN_IDENTITY"
export QUIETTYPE_CODESIGN_OPTIONS="${QUIETTYPE_CODESIGN_OPTIONS:---options runtime}"

swift test --arch x86_64 --disable-swift-testing
swift build -c release --arch arm64 --product LocalTypeMac
bash "$ROOT/scripts/package-app.sh"
codesign --verify --deep --strict --verbose=2 "$ROOT/dist/QuietType.app"
bash "$ROOT/scripts/create-dmg.sh"
DMG="$ROOT/dist/QuietType-${QUIETTYPE_VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/dist/QuietType.app/Contents/Info.plist" 2>/dev/null || echo "0.1.0")}-beta.${QUIETTYPE_BUILD:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$ROOT/dist/QuietType.app/Contents/Info.plist" 2>/dev/null || echo "1")}-macOS-arm64.dmg"
bash "$ROOT/scripts/verify-dmg-app.sh" "$DMG"

if [[ "$NOTARIZE" == "1" || "$NOTARIZE" == "true" ]]; then
  bash "$ROOT/scripts/notarize-dmg.sh"
  bash "$ROOT/scripts/verify-dmg-app.sh" "$DMG"
fi

echo
echo "Beta artifact ready:"
ls -lh "$ROOT"/dist/QuietType-*-macOS-arm64.dmg "$ROOT"/dist/QuietType-*-macOS-arm64.dmg.sha256
