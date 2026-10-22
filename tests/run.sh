#!/bin/sh
# Runs every shell and Lua test, plus each mod's tests when `claude` is installed. Exits non-zero if any test file fails.
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
if command -v claude >/dev/null 2>&1; then
  for m in "$HERE"/../mods/*/; do
    [ -d "$m" ] || continue
    printf '== mod %s\n' "$(basename "$m")"
    claude plugin test "$m" || status=1
  done
fi
exit $status
