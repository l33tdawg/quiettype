#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO="${SAGE_GITHUB_REPO:-l33tdawg/sage}"
TAG="${SAGE_RELEASE_TAG:-latest}"
OUT="${QUIETTYPE_SAGE_APP_SOURCE:-$ROOT/vendor/SAGE.app}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/quiettype-sage.XXXXXX")"

cleanup() {
  if [[ -d "$TMP/mount" ]]; then
    hdiutil detach "$TMP/mount" -quiet >/dev/null 2>&1 || true
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT

require_sage_app() {
  local sage_app="$1"
  local executable="$sage_app/Contents/MacOS/sage-gui"

  if [[ ! -d "$sage_app" ]]; then
    echo "SAGE.app not found at $sage_app" >&2
    exit 1
  fi

  if [[ ! -x "$executable" ]]; then
    echo "Downloaded SAGE.app is not runnable; missing executable: $executable" >&2
    exit 1
  fi
}

if [[ -d "$OUT" && "${QUIETTYPE_FORCE_SAGE_DOWNLOAD:-0}" != "1" ]]; then
  require_sage_app "$OUT"
  echo "$OUT"
  exit 0
fi

API_URL="https://api.github.com/repos/$REPO/releases/latest"
if [[ "$TAG" != "latest" ]]; then
  API_URL="https://api.github.com/repos/$REPO/releases/tags/$TAG"
fi

METADATA="$TMP/release.json"
curl -fsSL \
  -H "Accept: application/vnd.github+json" \
  -H "User-Agent: QuietType-SAGE-Bundler" \
  "$API_URL" \
  -o "$METADATA"

ASSET_URL="$(python3 - "$METADATA" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    release = json.load(handle)

assets = release.get("assets", [])
preferred = []
fallback = []
for asset in assets:
    name = asset.get("name", "").lower()
    url = asset.get("browser_download_url", "")
    if not url:
        continue
    is_macos = "macos" in name or "darwin" in name or name.endswith(".dmg")
    is_arm64 = "arm64" in name or "aarch64" in name
    if name.endswith((".dmg", ".zip")) and is_macos:
        fallback.append((name, url))
    if name.endswith(".dmg") and "sage" in name and is_macos and is_arm64:
        preferred.append((name, url))
    elif name.endswith(".zip") and "sage" in name and is_macos and is_arm64:
        preferred.append((name, url))

choice = (preferred or fallback)
if not choice:
    raise SystemExit("No SAGE macOS DMG/ZIP asset found in release.")
print(choice[0][1])
PY
)"

ASSET_NAME="$(basename "${ASSET_URL%%\?*}")"
ASSET="$TMP/$ASSET_NAME"
curl -fL \
  -H "Accept: application/octet-stream" \
  -H "User-Agent: QuietType-SAGE-Bundler" \
  "$ASSET_URL" \
  -o "$ASSET"

rm -rf "$OUT"
mkdir -p "$(dirname "$OUT")"

ASSET_NAME_LOWER="$(printf "%s" "$ASSET_NAME" | tr '[:upper:]' '[:lower:]')"

case "$ASSET_NAME_LOWER" in
  *.dmg)
    mkdir -p "$TMP/mount"
    hdiutil attach "$ASSET" -nobrowse -readonly -mountpoint "$TMP/mount" -quiet
    SAGE_APP="$(find "$TMP/mount" -maxdepth 3 -name "SAGE.app" -type d | head -n 1)"
    if [[ -z "$SAGE_APP" ]]; then
      echo "SAGE.app not found in $ASSET_NAME" >&2
      exit 1
    fi
    cp -R "$SAGE_APP" "$OUT"
    ;;
  *.zip)
    unzip -q "$ASSET" -d "$TMP/unzip"
    SAGE_APP="$(find "$TMP/unzip" -maxdepth 4 -name "SAGE.app" -type d | head -n 1)"
    if [[ -z "$SAGE_APP" ]]; then
      echo "SAGE.app not found in $ASSET_NAME" >&2
      exit 1
    fi
    cp -R "$SAGE_APP" "$OUT"
    ;;
  *)
    echo "Unsupported SAGE asset: $ASSET_NAME" >&2
    exit 1
    ;;
esac

require_sage_app "$OUT"

echo "$OUT"
