#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/dist/QuietType.app"
VERSION="${QUIETTYPE_VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null || echo "1.0.0")}"
BUILD="${QUIETTYPE_BUILD:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist" 2>/dev/null || echo "1")}"
RELEASE_LABEL="${QUIETTYPE_RELEASE_LABEL:-$(/usr/libexec/PlistBuddy -c 'Print :QuietTypeReleaseLabel' "$APP/Contents/Info.plist" 2>/dev/null || echo "beta.${BUILD}")}"
DMG="${QUIETTYPE_DMG:-$ROOT/dist/QuietType-${VERSION}-${RELEASE_LABEL}-macOS-arm64.dmg}"
PROFILE="${QUIETTYPE_NOTARY_PROFILE:-QUIETTYPE_NOTARY}"

if [[ ! -f "$DMG" ]]; then
  echo "Missing DMG: $DMG" >&2
  echo "Run scripts/beta-release.sh or scripts/create-dmg.sh first." >&2
  exit 1
fi

if ! xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
  cat >&2 <<EOF
Missing notarytool Keychain profile: $PROFILE

Create it once with:
  xcrun notarytool store-credentials "$PROFILE" \\
    --apple-id "YOUR_APPLE_ID" \\
    --team-id "2N7GKZ8D8Z" \\
    --password "APP_SPECIFIC_PASSWORD"

Use an app-specific password from appleid.apple.com. Do not commit credentials.
EOF
  exit 1
fi

echo "Submitting $DMG for notarization..."
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait

echo "Stapling notarization ticket..."
xcrun stapler staple "$DMG"

echo "Verifying Gatekeeper acceptance..."
spctl -a -t open --context context:primary-signature -v "$DMG"

(
  cd "$(dirname "$DMG")"
  shasum -a 256 "$(basename "$DMG")"
) > "$DMG.sha256"
echo "$DMG"
echo "$DMG.sha256"
