#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SWIFTPM_HOME="${SWIFTPM_HOME:-$ROOT/.swiftpm-home}"
CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$ROOT/.clang-module-cache}"
SIGN_IDENTITY="${QUIETTYPE_CODESIGN_IDENTITY:-Developer ID Application: Dhillon Kannabhiran (2N7GKZ8D8Z)}"
NOTARIZE="${QUIETTYPE_NOTARIZE:-0}"
INFO_PLIST="$ROOT/resources/LocalTypeMac/Info.plist"
DEFAULT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
DEFAULT_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST")"
DEFAULT_RELEASE_LABEL="$(/usr/libexec/PlistBuddy -c 'Print :QuietTypeReleaseLabel' "$INFO_PLIST")"

export SWIFTPM_HOME
export CLANG_MODULE_CACHE_PATH
export QUIETTYPE_VERSION="${QUIETTYPE_VERSION:-$DEFAULT_VERSION}"
export QUIETTYPE_BUILD="${QUIETTYPE_BUILD:-$DEFAULT_BUILD}"
export QUIETTYPE_RELEASE_LABEL="${QUIETTYPE_RELEASE_LABEL:-$DEFAULT_RELEASE_LABEL}"
export SAGE_RELEASE_TAG="${SAGE_RELEASE_TAG:-v11.4.11}"
export QUIETTYPE_CODESIGN_IDENTITY="$SIGN_IDENTITY"
export QUIETTYPE_CODESIGN_OPTIONS="${QUIETTYPE_CODESIGN_OPTIONS:---options runtime}"
export QUIETTYPE_REQUIRE_ASR_ASSETS="${QUIETTYPE_REQUIRE_ASR_ASSETS:-1}"

RELEASE_SUFFIX=""
if [[ -n "$QUIETTYPE_RELEASE_LABEL" ]]; then
  RELEASE_SUFFIX="-$QUIETTYPE_RELEASE_LABEL"
fi

bash "$ROOT/scripts/build-whisperkit-server.sh"
arch -arm64 swift test --arch arm64 --disable-swift-testing
arch -arm64 swift build -c release --arch arm64 --product LocalTypeMac
bash "$ROOT/scripts/package-app.sh"
codesign --verify --deep --strict --verbose=2 "$ROOT/dist/QuietType.app"
bash "$ROOT/scripts/create-dmg.sh"
DMG="$ROOT/dist/QuietType-${QUIETTYPE_VERSION}${RELEASE_SUFFIX}-macOS-arm64.dmg"
bash "$ROOT/scripts/verify-dmg-app.sh" "$DMG"

if [[ "$NOTARIZE" == "1" || "$NOTARIZE" == "true" ]]; then
  bash "$ROOT/scripts/notarize-dmg.sh"
  bash "$ROOT/scripts/verify-dmg-app.sh" "$DMG"
fi

echo
echo "Release artifact ready:"
ls -lh "$DMG" "$DMG.sha256"
