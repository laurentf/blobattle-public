#!/bin/sh
set -eu
mkdir -p out
(umask 077 && printf '[nakama]\nserver_key = %s\n' "${NAKAMA_SERVER_KEY:?missing from .env}" > out/nakama.ini)
started=$(date +%s%N)
java -jar /opt/defold/bob.jar --root client --platform wasm-web --architectures wasm-web \
  --variant release --archive --bundle-output out/web --settings "$(pwd)/out/nakama.ini" \
  --build-report-json out/web-report.json \
  resolve build bundle > out/web-build.log 2>&1 || { tail -40 out/web-build.log; exit 1; }
elapsed=$(( ($(date +%s%N) - started) / 1000000 ))
bytes=$(du -sb out/web/Blobattle | cut -f1)
echo "📦 HTML5 build: ${elapsed} ms, ${bytes} bytes in out/web/Blobattle"
