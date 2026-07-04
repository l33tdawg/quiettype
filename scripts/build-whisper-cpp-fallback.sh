#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/vendor/whisper.cpp"

if [[ ! -d "$SRC" ]]; then
  "$ROOT/scripts/build-whisper-cpp-metal.sh"
fi

cmake -S "$SRC" -B "$SRC/build-cpu" \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=OFF \
  -DWHISPER_BUILD_TESTS=OFF \
  -DWHISPER_BUILD_SERVER=OFF \
  -DWHISPER_BUILD_EXAMPLES=ON \
  -DWHISPER_SDL2=OFF \
  -DGGML_METAL=OFF

cmake --build "$SRC/build-cpu" --config Release --target whisper-cli -j"$(sysctl -n hw.ncpu)"

file "$SRC/build-cpu/bin/whisper-cli"
