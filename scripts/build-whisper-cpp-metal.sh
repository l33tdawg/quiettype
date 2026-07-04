#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR="$ROOT/vendor"
SRC="$VENDOR/whisper.cpp"
VERSION="v1.9.1"
ARCHIVE="$VENDOR/whisper.cpp-$VERSION.tar.gz"
URL="https://github.com/ggml-org/whisper.cpp/archive/refs/tags/$VERSION.tar.gz"
SHA256="147267177eef7b22ec3d2476dd514d1b12e160e176230b740e3d1bd600118447"

mkdir -p "$VENDOR"

if [[ ! -d "$SRC" ]]; then
  if [[ ! -f "$ARCHIVE" ]]; then
    curl -L "$URL" -o "$ARCHIVE"
  fi

  ACTUAL_SHA="$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')"
  if [[ "$ACTUAL_SHA" != "$SHA256" ]]; then
    echo "SHA256 mismatch for $ARCHIVE" >&2
    echo "expected $SHA256" >&2
    echo "actual   $ACTUAL_SHA" >&2
    exit 1
  fi

  TMP="$VENDOR/whisper.cpp-$VERSION-src"
  rm -rf "$TMP"
  mkdir -p "$TMP"
  tar -xzf "$ARCHIVE" -C "$TMP" --strip-components 1
  mv "$TMP" "$SRC"
fi

cmake -S "$SRC" -B "$SRC/build" \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=OFF \
  -DWHISPER_BUILD_TESTS=OFF \
  -DWHISPER_BUILD_SERVER=OFF \
  -DWHISPER_BUILD_EXAMPLES=ON \
  -DWHISPER_SDL2=OFF \
  -DGGML_METAL=ON

cmake --build "$SRC/build" --config Release --target whisper-cli -j"$(sysctl -n hw.ncpu)"

file "$SRC/build/bin/whisper-cli"
