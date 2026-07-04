#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SWIFTPM_HOME="${SWIFTPM_HOME:-$ROOT/.swiftpm-home}"
CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$ROOT/.clang-module-cache}"
SIGN_IDENTITY="${QUIETTYPE_CODESIGN_IDENTITY:-Developer ID Application: Dhillon Kannabhiran (2N7GKZ8D8Z)}"

export SWIFTPM_HOME
export CLANG_MODULE_CACHE_PATH
export QUIETTYPE_CODESIGN_IDENTITY="$SIGN_IDENTITY"
export QUIETTYPE_CODESIGN_OPTIONS="${QUIETTYPE_CODESIGN_OPTIONS:---options runtime}"

swift test --arch x86_64 --disable-swift-testing
swift build -c release --arch arm64 --product LocalTypeMac
bash "$ROOT/scripts/package-app.sh"
codesign --verify --deep --strict --verbose=2 "$ROOT/dist/QuietType.app"
bash "$ROOT/scripts/create-dmg.sh"

echo
echo "Beta artifact ready:"
ls -lh "$ROOT"/dist/QuietType-*-macOS-arm64.dmg "$ROOT"/dist/QuietType-*-macOS-arm64.dmg.sha256
