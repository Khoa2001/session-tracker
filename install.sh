#!/bin/sh
# Registers the wezterm-claude-kit hooks and the kit-band mod in <home>/.claude/settings.json.
# Usage: install.sh [--home DIR]
# Takes a timestamped backup first, is idempotent, and keeps existing hooks.
# The mod loads through CLAUDE_CODE_PLUGIN_DIRS. The kit's old status line is removed;
# a status line of your own is left alone.
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
# making every Claude hook fail.
hook_cmd="if [ -f '$HERE/hooks/track-state.sh' ]; then bash '$HERE/hooks/track-state.sh'; fi"
mod_dir="$HERE/mods/kit-band"
tmp=$(mktemp "$settings.tmp.XXXXXX")
trap 'rm -f "$tmp"' EXIT

jq --arg hook "$hook_cmd" --arg mod "$mod_dir" '
  def ours: {matcher: "*", hooks: [{type: "command", command: $hook, timeout: 5}]};
  reduce ("UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure",
          "PermissionRequest", "Notification", "Stop", "StopFailure",
          "SessionStart", "SessionEnd") as $ev (.;
    .hooks[$ev] = (
      (.hooks[$ev] // []) as $cur
      | if any($cur[]?; any(.hooks[]?; .command == $hook)) then $cur else $cur + [ours] end))
  | if (.statusLine.command // "" | contains("wezterm-claude-kit/statusline")) then del(.statusLine) else . end
  | .env.CLAUDE_CODE_PLUGIN_DIRS = (
      (.env.CLAUDE_CODE_PLUGIN_DIRS // "" | split(":") | map(select(. != ""))) as $dirs
      | (if ($dirs | index($mod)) == null then $dirs + [$mod] else $dirs end)
      | join(":"))
' "$settings" > "$tmp"

jq empty "$tmp"
mv "$tmp" "$settings"
trap - EXIT
mkdir -p "$HOME_DIR/.claude/state/panes"
echo "installed hooks and kit-band mod in $settings"
