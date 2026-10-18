#!/bin/sh
# Claude Code status line, one line per pane:
#   model │ ● repo branch │ +A -D ↑N base │ ctx bar pct (used/total)
# The dot comes from this pane's state file (see hooks/track-state.sh).
# Account usage (5h/7d) is not shown here; WezTerm shows it once.
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../lib/git-info.sh"

input=$(cat)

# --- model with per-model theme ---
model=$(echo "$input" | jq -r '.model.display_name // ""' 2>/dev/null)
model_id=$(echo "$input" | jq -r '.model.id // ""' 2>/dev/null)
case "$model_id" in
  *opus*)   model_color="38;2;236;72;153";  dir_color="38;2;251;164;200"; branch_color="38;2;200;110;220" ;;
  *sonnet*) model_color="38;2;245;166;35";  dir_color="38;2;250;204;110"; branch_color="38;2;230;130;70" ;;
  *haiku*)  model_color="38;2;45;212;191";  dir_color="38;2;110;231;215"; branch_color="38;2;56;160;220" ;;
  *fable*)  model_color="38;2;167;139;250"; dir_color="38;2;196;181;253"; branch_color="38;2;129;140;248" ;;
  *)        model_color="38;2;208;100;100"; dir_color="38;2;76;208;222";  branch_color="38;2;192;103;222" ;;
esac

dir=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // ""' 2>/dev/null)

# --- pane state dot ---
dot=""
state_dir=${SESSION_TRACKER_STATE_DIR:-$HOME/.claude/state/panes}
if [ -n "${WEZTERM_PANE:-}" ] && [ -f "$state_dir/$WEZTERM_PANE.json" ]; then
  case $(jq -r '.state // ""' "$state_dir/$WEZTERM_PANE.json" 2>/dev/null) in
    needs-you) dot="38;2;235;111;146" ;;
    working)   dot="38;2;246;193;119" ;;
    idle)      dot="38;2;152;195;121" ;;
  esac
fi

# --- git ---
repo=$(git_repo_name "$dir")
branch=$(git_branch "$dir")
added=0; deleted=0; ahead=""; base=""
if [ -n "$repo" ]; then
  set -- $(git_diff_stat "$dir"); added=$1; deleted=$2
  base=$(git_base_ref "$dir")
  [ -n "$base" ] && ahead=$(git_ahead "$dir" "$base")
fi

# Thin bar, 10 cells in half-cell steps: ━ filled, ╸ half step, ─ track.
# Prints "<filled><track>" with the filled part left uncolored; see ctx segment.
bar_fill() { # pct -> prints filled part
  steps=$(( ($1 * 20 + 50) / 100 ))
  [ "$steps" -lt 0 ] && steps=0
  [ "$steps" -gt 20 ] && steps=20
  full=$(( steps / 2 )); half=$(( steps % 2 ))
  out=""; i=0
  while [ "$i" -lt "$full" ]; do out="${out}━"; i=$((i + 1)); done
  [ "$half" -eq 1 ] && out="${out}╸"
  printf "%s" "$out"
}
bar_track() { # pct -> prints track part
  steps=$(( ($1 * 20 + 50) / 100 ))
  [ "$steps" -lt 0 ] && steps=0
  [ "$steps" -gt 20 ] && steps=20
  n=$(( 10 - (steps + 1) / 2 )); out=""; i=0
  while [ "$i" -lt "$n" ]; do out="${out}─"; i=$((i + 1)); done
  printf "%s" "$out"
}

SEP="\033[90m │ \033[0m"
first=1
sep() { if [ "$first" -eq 1 ]; then first=0; else printf "%b" "$SEP"; fi; }

# model
sep
printf "\033[%sm\033[1m%s\033[22m\033[0m" "$model_color" "$model"

# dot + repo + branch (repo falls back to the folder name outside a repo)
name=$repo
[ -z "$name" ] && name=$(basename "$dir")
if [ -n "$name" ]; then
  sep
  [ -n "$dot" ] && printf "\033[%sm●\033[0m " "$dot"
  printf "\033[1m\033[%sm%s\033[22m\033[0m" "$dir_color" "$name"
  [ -n "$branch" ] && printf " \033[1m\033[%sm%s\033[22m\033[0m" "$branch_color" "$branch"
fi

# diff + ahead
if [ "$added" -gt 0 ] || [ "$deleted" -gt 0 ] || { [ -n "$ahead" ] && [ "$ahead" -gt 0 ]; }; then
  sep
  s=""
  if [ "$added" -gt 0 ] || [ "$deleted" -gt 0 ]; then
    printf "\033[38;2;120;200;120m+%s\033[0m \033[38;2;220;120;120m-%s\033[0m" "$added" "$deleted"
    s=1
  fi
  if [ -n "$ahead" ] && [ "$ahead" -gt 0 ]; then
    [ -n "$s" ] && printf " "
    printf "\033[38;2;156;162;175m↑%s %s\033[0m" "$ahead" "$base"
  fi
fi

# context: thin bar, percent in a threshold color, used tokens dimmed
used=$(echo "$input" | jq -r '.context_window.used_percentage // empty' 2>/dev/null)
if [ -n "$used" ]; then
  sep
  pct=$(printf "%.0f" "$used")
  if [ "$pct" -lt 50 ]; then c="38;2;152;195;121"
  elif [ "$pct" -lt 80 ]; then c="38;2;232;180;80"
  else c="38;2;235;111;146"; fi
  printf "\033[%sm%s\033[38;2;74;72;88m%s\033[0m \033[%sm%s%%\033[0m" "$c" "$(bar_fill "$pct")" "$(bar_track "$pct")" "$c" "$pct"
  ctx_used=$(echo "$input" | jq -r '(.context_window.current_usage.cache_read_input_tokens + .context_window.current_usage.cache_creation_input_tokens + .context_window.current_usage.input_tokens + .context_window.current_usage.output_tokens) // empty' 2>/dev/null)
  [ -n "$ctx_used" ] && printf " \033[2m\033[38;2;156;162;175m%sk\033[0m" "$(( ctx_used / 1000 ))"
fi
