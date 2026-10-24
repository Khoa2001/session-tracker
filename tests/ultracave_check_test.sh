#!/bin/sh
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/lib.sh"
HOOK="$HERE/../hooks/ultracave-check.sh"

# run_hook TEXT [ACTIVE] -> hook stdout; builds a one-message transcript
run_hook() {
  d=$(new_tmp)
  jq -nc --arg t "$1" '{type:"assistant",message:{content:[{type:"text",text:$t}]}}' > "$d/t.jsonl"
  printf '{"transcript_path":"%s/t.jsonl","stop_hook_active":%s}' "$d" "${2:-false}" | sh "$HOOK"
}

test_blocks_filler_reply() {
  out=$(run_hook "Sure! I'd be happy to help you with that. The issue is that the token expiry check uses the wrong operator.")
  assert_eq "decision" block "$(printf '%s' "$out" | jq -r .decision)"
}

test_passes_terse_reply() {
  assert_eq "no output" "" "$(run_hook "Bug in auth middleware. Token expiry check use < not <=. Fix: change operator, rerun tests.")"
}

test_skips_when_stop_hook_active() {
  assert_eq "no output" "" "$(run_hook "Sure! I'd be happy to help you with that. The issue is that the token expiry check uses the wrong operator." true)"
}

test_skips_questions_and_short_replies() {
  assert_eq "question" "" "$(run_hook "Which settings file should the hook go into, the user one or the project one for this repo, and why would you prefer it?")"
  assert_eq "short" "" "$(run_hook "Sure, done.")"
}

test_ignores_code_blocks() {
  assert_eq "code ignored" "" "$(run_hook "Fix applied. Run:
\`\`\`
echo just the thing is really basically fine
\`\`\`
Tests pass.")"
}

test_exits_zero_on_bad_input() {
  printf 'garbage' | sh "$HOOK"; assert_eq "exit 0" 0 "$?"
  printf '{"transcript_path":"/nope"}' | sh "$HOOK"; assert_eq "exit 0 missing file" 0 "$?"
}

for t in test_blocks_filler_reply test_passes_terse_reply test_skips_when_stop_hook_active \
  test_skips_questions_and_short_replies test_ignores_code_blocks test_exits_zero_on_bad_input; do
  ( "$t" )
done
finish
