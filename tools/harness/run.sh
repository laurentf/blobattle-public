#!/bin/sh
set -eu
cd tools/harness
if ! cmp -s package-lock.json node_modules/.installed-lock; then
  npm ci --ignore-scripts --no-audit --no-fund --loglevel=error
  cp package-lock.json node_modules/.installed-lock
fi
exec node run.mjs "$@"
