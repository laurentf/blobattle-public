#!/bin/sh
set -eu
mkdir -p tmp/journey
part="${1:-all}"
node tools/web/serve.mjs out/web/Blobattle 5373 127.0.0.1 > tmp/journey/serve.log 2>&1 &
serve=$!
node tools/journey/forward.mjs 127.0.0.1:7550 blobattle-nakama:7350 > tmp/journey/forward.log 2>&1 &
forward=$!
chromium --no-sandbox --disable-dev-shm-usage --remote-debugging-port=9333 \
  --remote-debugging-address=127.0.0.1 --user-data-dir=/tmp/chromium \
  --use-angle=swiftshader --enable-unsafe-swiftshader --ignore-gpu-blocklist \
  ${JOURNEY_RESOLVE:+"--host-resolver-rules=MAP $JOURNEY_RESOLVE"} about:blank > tmp/journey/chromium.log 2>&1 &
browser=$!
trap 'kill $serve $forward $browser 2>/dev/null || true' EXIT
tries=0
until node -e "fetch('http://127.0.0.1:9333/json/version').then(() => process.exit(0), () => process.exit(1))" 2>/dev/null; do
  tries=$((tries + 1))
  if [ "$tries" -gt 150 ]; then
    echo "❌ Chromium did not start (tmp/journey/chromium.log)"
    exit 1
  fi
  sleep 0.2
done
status=0
if [ "$part" = "all" ] || [ "$part" = "offline" ]; then
  node tools/journey/run.mjs || status=1
fi
if [ "$part" = "all" ] || [ "$part" = "offline" ] || [ "$part" = "dynamite" ]; then
  node tools/journey/dynamite.mjs || status=1
fi
if [ "$part" = "all" ] || [ "$part" = "offline" ] || [ "$part" = "crates" ]; then
  node tools/journey/crates.mjs || status=1
fi
if [ "$part" = "all" ] || [ "$part" = "offline" ] || [ "$part" = "keys" ]; then
  node tools/journey/keys.mjs || status=1
fi
if [ "$part" = "all" ] || [ "$part" = "online" ]; then
  node tools/journey/online.mjs || status=1
fi
if [ "$part" = "all" ] || [ "$part" = "online" ] || [ "$part" = "quake" ]; then
  node tools/journey/quake.mjs || status=1
fi
exit $status
