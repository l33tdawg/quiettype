#!/usr/bin/env bash
set -euo pipefail

DMG="${1:-}"
if [[ -z "$DMG" ]]; then
  echo "Usage: scripts/verify-dmg-app.sh path/to/QuietType.dmg" >&2
  exit 2
fi

if [[ ! -f "$DMG" ]]; then
  echo "Missing DMG: $DMG" >&2
  exit 1
fi

MOUNT_POINT="$(mktemp -d "${TMPDIR:-/tmp}/quiettype-dmg-verify.XXXXXX")"
cleanup() {
  hdiutil detach "$MOUNT_POINT" -quiet >/dev/null 2>&1 || true
  rmdir "$MOUNT_POINT" >/dev/null 2>&1 || true
}
trap cleanup EXIT

hdiutil attach "$DMG" -nobrowse -readonly -mountpoint "$MOUNT_POINT" -quiet

APP="$MOUNT_POINT/QuietType.app"
if [[ ! -d "$APP" ]]; then
  echo "Mounted DMG does not contain QuietType.app" >&2
  exit 1
fi

codesign --verify --deep --strict --verbose=4 "$APP"
if [[ "${QUIETTYPE_VERIFY_MOUNTED_APP_GATEKEEPER:-0}" == "1" ]]; then
  spctl -a -vvv -t exec "$APP"
fi

echo "Mounted DMG app verification passed: $APP"
