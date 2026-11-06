#!/bin/sh
set -eu
base="http://blobattle-nakama:7350"
console="http://blobattle-nakama:7351"
status=0

check() {
  if [ "$2" = "ok" ]; then
    echo "✅ $1"
  else
    echo "❌ $1"
    status=1
  fi
}

if curl -fsS "$base/healthcheck" > /dev/null; then
  check "Nakama answers its healthcheck" ok
else
  check "Nakama answers its healthcheck" ko
fi

device="check-up-$(date +%s)-$$"
code=$(curl -s -o /dev/null -w '%{http_code}' -u "$NAKAMA_SERVER_KEY:" \
  -H 'Content-Type: application/json' -d "{\"id\":\"$device\"}" \
  "$base/v2/account/authenticate/device?create=true" || true)
[ "$code" = "200" ] && check "the server key from .env opens a session" ok \
  || check "the server key from .env opens a session (HTTP $code)" ko

code=$(curl -s -o /dev/null -w '%{http_code}' -u "defaultkey:" \
  -H 'Content-Type: application/json' -d "{\"id\":\"$device\"}" \
  "$base/v2/account/authenticate/device?create=true" || true)
[ "$code" = "401" ] && check "the default server key is refused" ok \
  || check "the default server key is refused (HTTP $code)" ko

token=$(curl -sS -H 'Content-Type: application/json' \
  -d "{\"username\":\"admin\",\"password\":\"$NAKAMA_CONSOLE_PASSWORD\"}" \
  "$console/v2/console/authenticate" | jq -r '.token // empty' 2> /dev/null || true)
[ -n "$token" ] && check "the console password from .env opens the console" ok \
  || check "the console password from .env opens the console" ko
modules=$(curl -sS -H "Authorization: Bearer $token" "$console/v2/console/runtime" \
  | jq -r '.lua_modules[]?.path' 2> /dev/null || true)
if echo "$modules" | grep -qx '/nakama/data/modules/server/room.lua'; then
  check "the room module is loaded" ok
else
  check "the room module is loaded" ko
fi

exit $status
