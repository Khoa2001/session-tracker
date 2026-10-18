#!/bin/sh
# Tiny assertion helpers for the session-tracker shell tests. Source this file.
# Each assert prints one PASS or FAIL line and records failures in $RESULTS,
# so tests can run in subshells and still be counted by `finish`.

TEST_TMP_ROOT=$(mktemp -d)
RESULTS="$TEST_TMP_ROOT/results"
: > "$RESULTS"
trap 'rm -rf "$TEST_TMP_ROOT"' EXIT

new_tmp() {
  mktemp -d "$TEST_TMP_ROOT/t.XXXXXX"
}

_pass() { printf 'PASS %s\n' "$1"; echo P >> "$RESULTS"; }
_fail() { printf 'FAIL %s\n  %s\n' "$1" "$2"; echo F >> "$RESULTS"; }

assert_eq() { # name expected actual
  if [ "$2" = "$3" ]; then _pass "$1"; else _fail "$1" "expected [$2] got [$3]"; fi
}

assert_contains() { # name haystack needle
  case "$2" in *"$3"*) _pass "$1" ;; *) _fail "$1" "[$2] does not contain [$3]" ;; esac
}

assert_not_contains() { # name haystack needle
  case "$2" in *"$3"*) _fail "$1" "[$2] contains [$3]" ;; *) _pass "$1" ;; esac
}

assert_file_missing() { # name path
  if [ ! -e "$2" ]; then _pass "$1"; else _fail "$1" "$2 exists"; fi
}

assert_file_exists() { # name path
  if [ -e "$2" ]; then _pass "$1"; else _fail "$1" "$2 missing"; fi
}

# Strip ANSI SGR escapes from stdin.
strip_ansi() {
  sed 's/\x1b\[[0-9;]*m//g'
}

finish() {
  fails=$(grep -c F "$RESULTS")
  passes=$(grep -c P "$RESULTS")
  printf '%s passed, %s failed\n' "$passes" "$fails"
  [ "$fails" -eq 0 ]
}
