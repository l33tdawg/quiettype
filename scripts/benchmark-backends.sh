#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUDIO="${1:-${TMPDIR:-/tmp}/quiettype-last.wav}"
NATIVE_URL="${QUIETTYPE_NATIVE_URL:-http://127.0.0.1:50060}"
GGML_MODEL="$HOME/Library/Application Support/QuietType/Models/ggml-small.en.bin"
WHISPER_CLI="$ROOT/dist/QuietType.app/Contents/MacOS/whisper-cli"

if [[ ! -f "$AUDIO" ]]; then
  echo "Missing audio file: $AUDIO" >&2
  exit 1
fi

echo "QuietType backend benchmark"
echo "Audio: $AUDIO"
echo

if curl -sS --max-time 2 "$NATIVE_URL/health" >/dev/null; then
  echo "Native WhisperKit: ready"
  native_start="$(python3 - <<'PY'
import time
print(time.time())
PY
)"
  native_output="$(curl -sS --max-time 45 \
    -X POST "$NATIVE_URL/v1/audio/transcriptions" \
    -F model=large-v3-v20240930_626MB \
    -F language=en \
    -F response_format=json \
    -F file=@"$AUDIO")"
  native_end="$(python3 - <<'PY'
import time
print(time.time())
PY
)"
  python3 - "$native_start" "$native_end" "$native_output" <<'PY'
import json
import sys

start = float(sys.argv[1])
end = float(sys.argv[2])
payload = sys.argv[3]
try:
    text = json.loads(payload).get("text", "").strip()
except Exception:
    text = payload.strip()
print(f"Native latency: {(end - start) * 1000:.0f} ms")
print(f"Native text: {text}")
PY
else
  echo "Native WhisperKit: not ready"
fi

echo

if [[ -x "$WHISPER_CLI" && -f "$GGML_MODEL" ]]; then
  echo "Bundled whisper.cpp fallback: ready"
  "$WHISPER_CLI" \
    -m "$GGML_MODEL" \
    -f "$AUDIO" \
    -l en \
    --no-timestamps \
    --suppress-nst \
    --no-speech-thold 0.25 \
    --threads 8 \
    --beam-size 1 \
    --best-of 2
else
  echo "Bundled whisper.cpp fallback: missing"
fi
