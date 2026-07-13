#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/dist/QuietType.app"
VERSION="${QUIETTYPE_VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null || echo "1.0.1")}"
BUILD="${QUIETTYPE_BUILD:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist" 2>/dev/null || echo "1")}"
RELEASE_LABEL="${QUIETTYPE_RELEASE_LABEL:-$(/usr/libexec/PlistBuddy -c 'Print :QuietTypeReleaseLabel' "$APP/Contents/Info.plist" 2>/dev/null || echo "beta.${BUILD}")}"
RELEASE_SUFFIX=""
VOLUME_SUFFIX=""
if [[ -n "$RELEASE_LABEL" ]]; then
  RELEASE_SUFFIX="-$RELEASE_LABEL"
  VOLUME_SUFFIX=" $RELEASE_LABEL"
fi
DMG_NAME="QuietType-${VERSION}${RELEASE_SUFFIX}-macOS-arm64.dmg"
VOLUME_NAME="QuietType ${VERSION}${VOLUME_SUFFIX}"
STAGING="$ROOT/dist/dmg-staging"
DMG="$ROOT/dist/$DMG_NAME"
TMP_DMG="$ROOT/dist/.tmp-$DMG_NAME"
SIGN_IDENTITY="${QUIETTYPE_CODESIGN_IDENTITY:-}"

if [[ ! -d "$APP" ]]; then
  echo "Missing app bundle: $APP" >&2
  echo "Run scripts/package-app.sh first." >&2
  exit 1
fi

rm -rf "$STAGING" "$DMG" "$TMP_DMG"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/QuietType.app"
ln -s /Applications "$STAGING/Applications"

hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING" \
  -ov \
  -format UDRW \
  "$TMP_DMG" >/dev/null

hdiutil convert "$TMP_DMG" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -o "$DMG" >/dev/null

rm -rf "$STAGING" "$TMP_DMG"

if [[ -n "$SIGN_IDENTITY" && "$SIGN_IDENTITY" != "-" ]]; then
  codesign --force --sign "$SIGN_IDENTITY" "$DMG" >/dev/null
fi

hdiutil verify "$DMG" >/dev/null
(
  cd "$(dirname "$DMG")"
  shasum -a 256 "$(basename "$DMG")"
) > "$DMG.sha256"

echo "$DMG"
echo "$DMG.sha256"
