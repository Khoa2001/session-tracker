#!/bin/sh
# Stop hook: block a reply that is not ultracave so Claude rewrites it terse.
# Heuristic only (filler phrases + article density). Must always exit 0.

input=$(cat)

[ "$(printf '%s' "$input" | jq -r '.stop_hook_active // false' 2>/dev/null)" = "true" ] && exit 0

transcript=$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)
[ -n "$transcript" ] && [ -f "$transcript" ] || exit 0

# Last assistant text block of the transcript.
text=$(jq -rs '[.[] | select(.type == "assistant") | .message.content[]? | select(.type == "text") | .text] | last // empty' "$transcript" 2>/dev/null)
[ -n "$text" ] || exit 0

# Drop fenced code, inline code and URLs: those stay normal.
prose=$(printf '%s\n' "$text" | awk '/^```/{f=!f; next} !f' | sed -E 's/`[^`]*`//g; s#https?://[^ ]+##g' | tr 'A-Z' 'a-z')

words=$(printf '%s' "$prose" | wc -w | tr -d ' ')
[ "${words:-0}" -ge 12 ] || exit 0

# Plain prose is allowed for questions and security or irreversible warnings.
case "$prose" in
  *warning*|*irreversible*|*"security"*) exit 0 ;;
esac
printf '%s' "$prose" | tail -c 3 | grep -q '?' && exit 0

filler=$(printf '%s' "$prose" | grep -oE "\b(sure|certainly|of course|happy to|i'd be|i'll|let me know|great question|basically|actually|really|simply|just|i think|it seems|you might want|feel free|hope this helps)\b" | wc -l | tr -d ' ')
articles=$(printf '%s' "$prose" | tr -c "a-z'" '\n' | grep -cxE 'a|an|the')

# Ultracave drops articles: flag any filler, or articles above 4% of words.
if [ "$filler" -ge 1 ] || [ $((articles * 100)) -gt $((words * 4)) ]; then
  jq -n --arg r "Reply not ultracave (filler=$filler, articles=$articles/$words words). Resend same content: drop articles, filler, pleasantries, hedging; fragments; keep code and technical terms exact." \
    '{decision: "block", reason: $r}'
fi
exit 0
