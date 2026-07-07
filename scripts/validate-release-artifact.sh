#!/usr/bin/env bash
set -euo pipefail

DMG="${1:-}"
if [[ -z "$DMG" ]]; then
  echo "Usage: scripts/validate-release-artifact.sh path/to/QuietType.dmg" >&2
  exit 2
fi

if [[ ! -f "$DMG" ]]; then
  echo "Missing DMG: $DMG" >&2
  exit 1
fi

MOUNT_POINT="$(mktemp -d "${TMPDIR:-/tmp}/quiettype-release-validate.XXXXXX")"
cleanup() {
  hdiutil detach "$MOUNT_POINT" -quiet >/dev/null 2>&1 || true
  rmdir "$MOUNT_POINT" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "Attaching $DMG"
hdiutil attach "$DMG" -nobrowse -readonly -mountpoint "$MOUNT_POINT" -quiet

APP="$MOUNT_POINT/QuietType.app"
if [[ ! -d "$APP" ]]; then
  echo "Mounted DMG does not contain QuietType.app" >&2
  exit 1
fi

PLIST="$APP/Contents/Info.plist"
EXECUTABLE_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$PLIST")"
EXECUTABLE="$APP/Contents/MacOS/$EXECUTABLE_NAME"
if [[ ! -x "$EXECUTABLE" ]]; then
  echo "CFBundleExecutable is missing or not executable: $EXECUTABLE" >&2
  exit 1
fi

echo "Verifying outer app signature"
codesign --verify --deep --strict --verbose=4 "$APP"

echo "Inspecting outer app entitlements"
codesign -d --entitlements - "$APP" >/dev/null

echo "Verifying main executable signature"
codesign --verify --strict --verbose=4 "$EXECUTABLE"

for helper in argmax-cli whisper-cli; do
  helper_path="$APP/Contents/MacOS/$helper"
  if [[ -e "$helper_path" ]]; then
    if [[ ! -x "$helper_path" ]]; then
      echo "Helper exists but is not executable: $helper_path" >&2
      exit 1
    fi
    echo "Verifying helper signature: $helper"
    codesign --verify --strict --verbose=4 "$helper_path"
  fi
done

SAGE_APP="$APP/Contents/Resources/SAGE.app"
if [[ -d "$SAGE_APP" ]]; then
  echo "Verifying bundled SAGE.app signature"
  codesign --verify --deep --strict --verbose=4 "$SAGE_APP"
  for sage_helper in sage-tray sage-gui; do
    sage_helper_path="$SAGE_APP/Contents/MacOS/$sage_helper"
    if [[ -e "$sage_helper_path" ]]; then
      if [[ ! -x "$sage_helper_path" ]]; then
        echo "SAGE helper exists but is not executable: $sage_helper_path" >&2
        exit 1
      fi
      codesign --verify --strict --verbose=4 "$sage_helper_path"
    fi
  done
fi

if [[ "${QUIETTYPE_VALIDATE_GATEKEEPER:-1}" == "1" ]]; then
  echo "Assessing mounted app with Gatekeeper"
  spctl --assess --type execute --verbose=4 "$APP"
fi

if [[ "${QUIETTYPE_VALIDATE_DMG_GATEKEEPER:-1}" == "1" ]]; then
  echo "Assessing DMG with Gatekeeper"
  spctl --assess --type open --context context:primary-signature --verbose=4 "$DMG"
fi

if [[ "${QUIETTYPE_VALIDATE_LAUNCH:-0}" == "1" ]]; then
  echo "Running optional Launch Services open check"
  open "$APP"
fi

echo "Release artifact validation passed: $DMG"
