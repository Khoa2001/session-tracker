#!/bin/sh
# UserPromptSubmit hook: if ultracave-check.sh flagged the last reply of this
# session, tell Claude once to stay terse. Always exits 0.

input=$(cat)
sid=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)
[ -n "$sid" ] || exit 0
dir=${SESSION_TRACKER_ULTRACAVE_DIR:-$HOME/.claude/state/ultracave}
flag="$dir/$sid"
[ -f "$flag" ] || exit 0

why=$(cat "$flag" 2>/dev/null)
rm -f "$flag"
jq -n --arg c "Your last reply broke ultracave ($why). Stay ultracave: drop articles, filler, pleasantries, hedging; fragments; code and technical terms exact." \
  '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $c}}'
exit 0
