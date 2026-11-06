#!/bin/sh
set -eu
base="http://blobattle-check-nakama:7350/v2/rpc"
key="conformance"
status=0
for file in spec/vectors/*.lua; do
  name=$(basename "$file" .lua)
  [ "$name" = "index" ] && continue
  luajit tools/conformance/local.lua "$name" expected > "/tmp/$name.expected"
  for engine in luajit lua5.1; do
    "$engine" tools/conformance/local.lua "$name" > "/tmp/$name.$engine"
  done
  curl -fsS -X POST "$base/conformance_vector?http_key=$key&unwrap" \
    -H 'Content-Type: application/json' -d "{\"name\":\"$name\"}" > "/tmp/$name.json"
  jq -r '(.sums[] | "\(.tick) \(.a) \(.b)"), .names[]' "/tmp/$name.json" > "/tmp/$name.nakama"
  if [ -s "/tmp/$name.expected" ] \
    && cmp -s "/tmp/$name.expected" "/tmp/$name.luajit" \
    && cmp -s "/tmp/$name.expected" "/tmp/$name.lua5.1" \
    && cmp -s "/tmp/$name.expected" "/tmp/$name.nakama"; then
    echo "🧮 $name: $(grep -vc '^team ' "/tmp/$name.expected") recorded sums and $(grep -c '^team ' "/tmp/$name.expected") team names found under LuaJIT, Lua 5.1 and Nakama"
  else
    echo "❌ $name diverges"
    paste "/tmp/$name.expected" "/tmp/$name.luajit" "/tmp/$name.lua5.1" "/tmp/$name.nakama" | head -20
    status=1
  fi
done
measure() {
  curl -fsS -X POST "$base/conformance_measure?http_key=$key&unwrap" \
    -H 'Content-Type: application/json' -d "$1"
}
measure '{"what":"map"}' > /tmp/map.json
measure '{"what":"tick"}' > /tmp/tick.json
measure '{"what":"snapshot"}' > /tmp/snapshot.json
for level in easy medium hard; do
  measure "{\"what\":\"bot\",\"level\":\"$level\"}"
done | jq -s '.' > /tmp/bots.json
jq -r '"⏱️ Nakama: largest map \(.largest_map_ms) ms"' /tmp/map.json
jq -r '"⏱️ Nakama: one sim tick of brawl \(.brawl_tick_ms) ms"' /tmp/tick.json
jq -r '"📦 Nakama, snapshot of the largest map: \(.snapshot_cold_ms) ms after a crater, \(.snapshot_cached_ms) ms from the cache, \(.encode_ms) ms to JSON, \(.bytes) bytes"' /tmp/snapshot.json
jq -r '.[] | "🤖 Nakama, \(.level) bot at the server budget: \(.calls) calls, \(.avg_ms) ms on average, p90 \(.p90_ms) ms, worst \(.max_ms) ms, \(.over_8ms) calls over 8 ms, \(.work) units of work at \(.unit_us) µs"' /tmp/bots.json
if ! jq -e '.largest_map_ms < 3000' /tmp/map.json > /dev/null; then
  echo "❌ the largest map takes 3 s or more in Nakama (§5.3)"
  status=1
fi
if ! jq -e '[.[].max_ms] | max < 33' /tmp/bots.json > /dev/null; then
  echo "❌ a bot call takes a whole tick (33 ms) or more at the server budget in Nakama (§9)"
  status=1
fi
exit $status
