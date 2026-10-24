#!/bin/sh
# Stop hook: flag a reply that is not ultracave. Never blocks (a block prints
# a "Stop hook error" row); hooks/ultracave-remind.sh reads the flag on the
# next prompt. Heuristic only (filler phrases + article density). Must always
# exit 0 and print nothing.

input=$(cat)

[ "$(printf '%s' "$input" | jq -r '.stop_hook_active // false' 2>/dev/null)" = "true" ] && exit 0

# The Stop payload carries the reply itself. The transcript can lag behind at
# Stop time and still hold the previous reply, so it is only a fallback.
text=$(printf '%s' "$input" | jq -r '.last_assistant_message // empty' 2>/dev/null)
if [ -z "$text" ]; then
  transcript=$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)
  [ -n "$transcript" ] && [ -f "$transcript" ] || exit 0
  text=$(jq -rs '[.[] | select(.type == "assistant") | .message.content[]? | select(.type == "text") | .text] | last // empty' "$transcript" 2>/dev/null)
fi
[ -n "$text" ] || exit 0

# Drop fenced code, inline code and URLs: those stay normal.
prose=$(printf '%s\n' "$text" | awk '/^```/{f=!f; next} !f' | sed -E 's/`[^`]*`//g; s#https?://[^ ]+##g' | tr 'A-Z' 'a-z')

words=$(printf '%s' "$prose" | wc -w | tr -d ' ')
[ "${words:-0}" -ge 30 ] || exit 0

# Plain prose is allowed for questions and security or irreversible warnings.
case "$prose" in
  *warning*|*irreversible*|*"security"*) exit 0 ;;
esac
printf '%s' "$prose" | tail -c 3 | grep -q '?' && exit 0

filler=$(printf '%s' "$prose" | grep -oE "\b(sure|certainly|of course|happy to|i'd be|i'll|let me know|great question|basically|actually|really|simply|just|i think|it seems|you might want|feel free|hope this helps)\b" | wc -l | tr -d ' ')
articles=$(printf '%s' "$prose" | tr -c "a-z'" '\n' | grep -cxE 'a|an|the')

# Ultracave drops articles: flag any filler, or articles above 4% of words.
if [ "$filler" -ge 1 ] || [ $((articles * 100)) -gt $((words * 4)) ]; then
  sid=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)
  [ -n "$sid" ] || exit 0
  dir=${SESSION_TRACKER_ULTRACAVE_DIR:-$HOME/.claude/state/ultracave}
  mkdir -p "$dir" 2>/dev/null || exit 0
  printf 'filler=%s, articles=%s/%s words' "$filler" "$articles" "$words" > "$dir/$sid" 2>/dev/null
fi
exit 0
