#!/bin/sh
# Registers the wezterm-claude-kit hooks and status line in <home>/.claude/settings.json.
# Usage: install.sh [--home DIR]
# Takes a timestamped backup first, is idempotent, and keeps existing hooks.
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
HOME_DIR=$HOME
if [ "${1:-}" = "--home" ]; then HOME_DIR=${2:?--home needs a directory}; fi

settings="$HOME_DIR/.claude/settings.json"
if [ ! -f "$settings" ]; then
  echo "settings.json not found: $settings" >&2
  exit 1
fi
jq empty "$settings" 2>/dev/null || { echo "settings.json is not valid JSON: $settings" >&2; exit 1; }

backup="$settings.bak-$(date +%Y%m%d-%H%M%S)"
cp "$settings" "$backup"
echo "backup: $backup"

# Guarded so a moved or deleted project folder degrades quietly instead of
# making every Claude hook fail or blanking the status line.
hook_cmd="if [ -f '$HERE/hooks/track-state.sh' ]; then bash '$HERE/hooks/track-state.sh'; fi"
sl_cmd="if [ -f '$HERE/statusline/statusline-command.sh' ]; then bash '$HERE/statusline/statusline-command.sh'; else bash ~/.claude/statusline-command.sh; fi"
tmp=$(mktemp "$settings.tmp.XXXXXX")
trap 'rm -f "$tmp"' EXIT

jq --arg hook "$hook_cmd" --arg sl "$sl_cmd" '
  def ours: {matcher: "*", hooks: [{type: "command", command: $hook, timeout: 5}]};
  reduce ("UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure",
          "PermissionRequest", "Notification", "Stop", "StopFailure",
          "SessionStart", "SessionEnd") as $ev (.;
    .hooks[$ev] = (
      (.hooks[$ev] // []) as $cur
      | if any($cur[]?; any(.hooks[]?; .command == $hook)) then $cur else $cur + [ours] end))
  | .statusLine.type = "command"
  | .statusLine.command = $sl
' "$settings" > "$tmp"

jq empty "$tmp"
mv "$tmp" "$settings"
trap - EXIT
mkdir -p "$HOME_DIR/.claude/state/panes"
echo "installed hooks and status line in $settings"
