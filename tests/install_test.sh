#!/bin/sh
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/lib.sh"
TOOLS=$(cd "$HERE/.." && pwd)
INSTALL="$TOOLS/install.sh"
UNINSTALL="$TOOLS/uninstall.sh"
HOOK_CMD="if [ -f '$TOOLS/hooks/track-state.sh' ]; then bash '$TOOLS/hooks/track-state.sh'; fi"
MOD_DIR="$TOOLS/mods/kit-band"
OLD_SL_CMD="if [ -f '$TOOLS/statusline/statusline-command.sh' ]; then bash '$TOOLS/statusline/statusline-command.sh'; else bash ~/.claude/statusline-command.sh; fi"
EVENTS="UserPromptSubmit PreToolUse PostToolUse PostToolUseFailure PermissionRequest Notification Stop StopFailure SessionStart SessionEnd"

# seed_home -> fake HOME with a settings.json shaped like the real one
seed_home() {
  h=$(new_tmp)
  mkdir -p "$h/.claude"
  cat > "$h/.claude/settings.json" <<'EOF'
{"model":"sonnet",
 "hooks":{
  "Notification":[],
  "Stop":[
   {"matcher":"","hooks":[{"type":"command","command":"bash ~/.claude/fetch-usage.sh > /dev/null 2>&1 &"}]},
   {"hooks":[{"type":"command","command":"if [ -x '/h/.orca/agent-hooks/claude-hook.sh' ]; then /bin/sh '/h/.orca/agent-hooks/claude-hook.sh'; fi"}]}],
  "SessionStart":[{"hooks":[{"type":"command","command":"bash '/h/.claude/hooks/herdr-agent-state.sh' session"}]}]},
 "statusLine":{"type":"command","command":"bash ~/.claude/statusline-command.sh"}}
EOF
  echo "$h"
}

settings() { echo "$1/.claude/settings.json"; }

# number of entries under event $2 whose command is ours
ours_count() {
  jq --arg ev "$2" --arg c "$HOOK_CMD" \
    '[.hooks[$ev][]? | .hooks[]? | select(.command == $c)] | length' "$(settings "$1")"
}

test_install_adds_all_ten_events() {
  h=$(seed_home)
  sh "$INSTALL" --home "$h" >/dev/null
  for ev in $EVENTS; do
    assert_eq "ours once in $ev" 1 "$(ours_count "$h" "$ev")"
  done
}

test_install_is_idempotent() {
  h=$(seed_home)
  sh "$INSTALL" --home "$h" >/dev/null
  first=$(jq -S . "$(settings "$h")")
  sh "$INSTALL" --home "$h" >/dev/null
  assert_eq "second install changes nothing" "$first" "$(jq -S . "$(settings "$h")")"
}

test_install_preserves_existing_hooks_and_order() {
  h=$(seed_home)
  sh "$INSTALL" --home "$h" >/dev/null
  s=$(settings "$h")
  assert_contains "fetch-usage first in Stop" "$(jq -r '.hooks.Stop[0].hooks[0].command' "$s")" "fetch-usage.sh"
  assert_contains "orca second in Stop" "$(jq -r '.hooks.Stop[1].hooks[0].command' "$s")" "orca"
  assert_contains "herdr still first in SessionStart" "$(jq -r '.hooks.SessionStart[0].hooks[0].command' "$s")" "herdr"
  assert_eq "other settings kept" sonnet "$(jq -r .model "$s")"
}

test_install_loads_mod() {
  h=$(seed_home)
  sh "$INSTALL" --home "$h" >/dev/null
  assert_eq "plugin dirs" "$MOD_DIR" "$(jq -r .env.CLAUDE_CODE_PLUGIN_DIRS "$(settings "$h")")"
}

test_install_keeps_other_plugin_dirs() {
  h=$(seed_home)
  jq '.env.CLAUDE_CODE_PLUGIN_DIRS = "/x/mine:/x/other"' "$(settings "$h")" > "$h/s.json" && mv "$h/s.json" "$(settings "$h")"
  sh "$INSTALL" --home "$h" >/dev/null
  sh "$INSTALL" --home "$h" >/dev/null
  assert_eq "ours appended once" "/x/mine:/x/other:$MOD_DIR" "$(jq -r .env.CLAUDE_CODE_PLUGIN_DIRS "$(settings "$h")")"
}

test_install_leaves_own_statusline() {
  h=$(seed_home)
  sh "$INSTALL" --home "$h" >/dev/null
  assert_eq "user status line kept" "bash ~/.claude/statusline-command.sh" "$(jq -r .statusLine.command "$(settings "$h")")"
}

test_install_removes_kit_statusline() {
  h=$(seed_home)
  jq --arg c "$OLD_SL_CMD" '.statusLine = {type:"command", command:$c, refreshInterval:3}' "$(settings "$h")" > "$h/s.json" && mv "$h/s.json" "$(settings "$h")"
  sh "$INSTALL" --home "$h" >/dev/null
  assert_eq "kit status line gone" null "$(jq -r '.statusLine // null' "$(settings "$h")")"
}

test_install_creates_backup() {
  h=$(seed_home)
  orig=$(jq -S . "$(settings "$h")")
  sh "$INSTALL" --home "$h" >/dev/null
  n=$(ls "$h/.claude" | grep -c '^settings.json.bak-')
  assert_eq "one backup" 1 "$n"
  assert_eq "backup equals original" "$orig" "$(jq -S . "$h"/.claude/settings.json.bak-*)"
}

test_install_output_is_valid_json() {
  h=$(seed_home)
  sh "$INSTALL" --home "$h" >/dev/null
  jq empty "$(settings "$h")" 2>/dev/null
  assert_eq "valid json" 0 "$?"
}

test_uninstall_removes_only_ours() {
  h=$(seed_home)
  norm='walk(if type == "object" then with_entries(select(.value != [] and .value != {})) else . end)'
  orig=$(jq -S "$norm" "$(settings "$h")")
  sh "$INSTALL" --home "$h" >/dev/null
  sh "$UNINSTALL" --home "$h" >/dev/null
  assert_eq "back to original (ignoring empty arrays)" "$orig" "$(jq -S "$norm" "$(settings "$h")")"
}

test_missing_settings_file_fails_cleanly() {
  h=$(new_tmp)
  out=$(sh "$INSTALL" --home "$h" 2>&1); rc=$?
  assert_eq "non-zero exit" 1 "$([ "$rc" -ne 0 ] && echo 1 || echo 0)"
  assert_contains "message" "$out" "settings.json"
  assert_file_missing "no settings created" "$h/.claude/settings.json"
}

for t in test_install_adds_all_ten_events test_install_is_idempotent \
  test_install_preserves_existing_hooks_and_order test_install_loads_mod \
  test_install_keeps_other_plugin_dirs test_install_leaves_own_statusline \
  test_install_removes_kit_statusline test_install_creates_backup test_install_output_is_valid_json \
  test_uninstall_removes_only_ours \
  test_missing_settings_file_fails_cleanly; do
  ( "$t" )
done
finish
