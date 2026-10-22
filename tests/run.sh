#!/bin/sh
# Runs every shell and Lua test. Exits non-zero if any test file fails.
HERE=$(cd "$(dirname "$0")" && pwd)
status=0
for t in "$HERE"/*_test.sh; do
  [ -e "$t" ] || continue
  printf '== %s\n' "$(basename "$t")"
  sh "$t" || status=1
done
for t in "$HERE"/*_test.lua; do
  [ -e "$t" ] || continue
  printf '== %s\n' "$(basename "$t")"
  luajit "$t" || status=1
done
exit $status
