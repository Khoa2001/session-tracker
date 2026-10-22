#!/bin/sh
# Claude Code status line, one line per pane:
#   N model  repo branch │ ±N ↑N │ pct
# N is the pane number in a rounded solid block (only while the tab has several panes), model is its short name, dimmed.
# Account usage (5h/7d) is not shown here; WezTerm shows it once.
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../lib/git-info.sh"

input=$(cat)

# --- model name and per-model theme ---
model_id=$(echo "$input" | jq -r '.model.id // ""' 2>/dev/null)
case "$model_id" in
  *opus*)   model_name="opus";   dir_color="38;2;251;164;200"; branch_color="38;2;200;110;220" ;;
  *sonnet*) model_name="sonnet"; dir_color="38;2;250;204;110"; branch_color="38;2;230;130;70" ;;
  *haiku*)  model_name="haiku";  dir_color="38;2;110;231;215"; branch_color="38;2;56;160;220" ;;
  *fable*)  model_name="fable";  dir_color="38;2;196;181;253"; branch_color="38;2;129;140;248" ;;
  *)        model_name="claude"; dir_color="38;2;76;208;222";  branch_color="38;2;192;103;222" ;;
esac

dir=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // ""' 2>/dev/null)

state_dir=${SESSION_TRACKER_STATE_DIR:-$HOME/.claude/state/panes}

# --- git ---
repo=$(git_repo_name "$dir")
branch=$(git_branch "$dir")
added=0; deleted=0; ahead=""; base=""
if [ -n "$repo" ]; then
  set -- $(git_diff_stat "$dir"); added=$1; deleted=$2
  base=$(git_base_ref "$dir")
  [ -n "$base" ] && ahead=$(git_ahead "$dir" "$base")
fi

# Cap a name at 14 characters, ending in an ellipsis. jq only runs when the byte
# length is over the cap, so plain short names cost nothing and UTF-8 stays whole.
cap() {
  if [ "${#1}" -le 14 ]; then printf "%s" "$1"
  else printf "%s" "$1" | jq -Rrj 'if length > 14 then .[0:13] + "…" else . end'; fi
}

# Branch without its conventional type prefix (feat/, fix/, ...).
short_branch() {
  case $1 in
    feat/*|fix/*|chore/*|refactor/*|docs/*|test/*|perf/*|build/*|ci/*|style/*|revert/*|hotfix/*) printf "%s" "${1#*/}" ;;
    *) printf "%s" "$1" ;;
  esac
}

# Width of the pane this status line sits in. Claude Code gives the script no tty
# and no width, so walk up the parents to the first one with a terminal and ask
# it. Empty when unknown, which means "never shorten".
term_cols() {
  if [ -n "${SESSION_TRACKER_COLS:-}" ]; then printf "%s" "$SESSION_TRACKER_COLS"; return 0; fi
  p=$$; n=0
  while [ "$n" -lt 8 ] && [ -n "$p" ] && [ "$p" -gt 1 ]; do
    t=$(ps -o tty= -p "$p" 2>/dev/null | tr -d ' ')
    case $t in
      ''|'?'|'??') ;;
      *)
        sz=$(stty -f "/dev/$t" size 2>/dev/null || stty -F "/dev/$t" size 2>/dev/null)
        printf "%s" "${sz#* }"
        return 0
        ;;
    esac
    p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' '); n=$((n + 1))
  done
}

SEP="\033[90m │ \033[0m"
first=1
sep() { if [ "$first" -eq 1 ]; then first=0; else printf "%b" "$SEP"; fi; }

# Pane number badge, written by wezterm/tracker.lua while the tab has several panes.
# The same hue also colors repo and branch, so a pane reads as one color.
num_w=0
if [ -n "${WEZTERM_PANE:-}" ] && [ -f "$state_dir/$WEZTERM_PANE.pos" ]; then
  read -r pane_no < "$state_dir/$WEZTERM_PANE.pos" 2>/dev/null
  case $pane_no in
    ''|*[!0-9]*) ;;
    *)
      case $(( (pane_no - 1) % 6 )) in
        0) hue="224;108;117" ;; 1) hue="229;192;123" ;; 2) hue="198;120;221" ;;
        3) hue="86;182;194" ;; 4) hue="152;195;121" ;; *) hue="97;175;239" ;;
      esac
      dir_color="38;2;$hue"; branch_color="38;2;$hue"
      badge_fg="46;52;64"
      # half-circle caps (Powerline U+E0B6 / U+E0B4) round the block
      printf "\033[38;2;%sm\356\202\266\033[48;2;%s;38;2;%s;1m%s\033[0m\033[38;2;%sm\356\202\264\033[0m " \
        "$hue" "$hue" "$badge_fg" "$pane_no" "$hue"
      num_w=$(( ${#pane_no} + 3 ))
      ;;
  esac
fi

name=$repo
[ -z "$name" ] && name=$(basename "$dir")

# context percent, computed first because it is the last thing to be dropped
pct=""
used=$(echo "$input" | jq -r '.context_window.used_percentage // empty' 2>/dev/null)
[ -n "$used" ] && pct=$(printf "%.0f" "$used")

# changed lines (added plus deleted) and commits ahead, as plain text
# (^ stands for the arrow so lengths count columns)
changed=$(( added + deleted ))
diff_plain=""
if [ "$changed" -gt 0 ]; then diff_plain="±$changed"; fi
if [ -n "$ahead" ] && [ "$ahead" -gt 0 ]; then
  diff_plain="${diff_plain:+$diff_plain }^$ahead"
fi

# Fit to the pane: drop diff, then shorten the branch, then drop it, then cap the
# repo, and stop at the first layout that fits. Unknown width shows everything.
show_diff=1; show_branch=1; branch_txt=$branch; name_txt=$name
cols=$(term_cols)
case $cols in ''|*[!0-9]*) cols="" ;; esac
if [ -n "$cols" ]; then
  avail=$(( cols - 2 ))
  # width of: number, model, its trailing space, repo, branch (with its space), diff segment, percent segment
  fits() {
    w=$(( num_w + ${#model_name} + 1 ))
    [ -n "$name_txt" ] && w=$(( w + 1 + ${#name_txt} ))
    [ "$show_branch" -eq 1 ] && [ -n "$branch_txt" ] && w=$(( w + 1 + ${#branch_txt} ))
    [ "$show_diff" -eq 1 ] && [ -n "$diff_plain" ] && w=$(( w + 3 + ${#diff_plain} ))
    [ -n "$pct" ] && w=$(( w + 3 + ${#pct} + 1 ))
    [ "$w" -le "$avail" ]
  }
  fits || show_diff=0
  fits || branch_txt=$(cap "$(short_branch "$branch")")
  fits || show_branch=0
  fits || name_txt=$(cap "$name")
fi

# model name + repo + branch (repo falls back to the folder name outside a repo)
sep
printf "\033[38;2;156;162;175m%s\033[0m" "$model_name"
if [ -n "$name_txt" ]; then
  printf "  "
  printf "\033[1m\033[%sm%s\033[22m\033[0m" "$dir_color" "$name_txt"
  [ "$show_branch" -eq 1 ] && [ -n "$branch_txt" ] && printf " \033[%sm%s\033[0m" "$branch_color" "$branch_txt"
fi

# diff + ahead
if [ "$show_diff" -eq 1 ] && [ -n "$diff_plain" ]; then
  sep
  s=""
  if [ "$changed" -gt 0 ]; then
    printf "\033[38;2;232;180;80m±%s\033[0m" "$changed"
    s=1
  fi
  if [ -n "$ahead" ] && [ "$ahead" -gt 0 ]; then
    [ -n "$s" ] && printf " "
    printf "\033[38;2;156;162;175m↑%s\033[0m" "$ahead"
  fi
fi

# context: percent in a threshold color
if [ -n "$pct" ]; then
  sep
  if [ "$pct" -lt 50 ]; then c="38;2;152;195;121"
  elif [ "$pct" -lt 80 ]; then c="38;2;232;180;80"
  else c="38;2;235;111;146"; fi
  printf "\033[1m\033[%sm%s%%\033[22m\033[0m" "$c" "$pct"
fi
