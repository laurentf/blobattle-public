#!/bin/sh
set -eu
run="${1:-default}"
shift || true
engines="${*:-luajit lua5.1}"
for engine in $engines; do
  echo "── busted ($run) under $engine"
  BLOBATTLE_LUA="$engine" busted --lua="$engine" --run="$run"
done
