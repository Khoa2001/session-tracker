# Session tracker

Shows the state of every Claude Code session running in WezTerm panes.

- **Hooks** (`hooks/track-state.sh`) write one file per pane, `~/.claude/state/panes/<WEZTERM_PANE>.json`:
  `{"state","repo","branch","cwd","session_id","ts"}`. States: `working`, `needs-you`, `idle`.
- **Status line** (`statusline/statusline-command.sh`): `model | dot repo branch | +A -D ↑N base | ctx`.
- **WezTerm** (`wezterm/`): a state dot in each tab title (worst state among the tab's panes), and on the
  right of the tab bar the counts plus 5h/7d usage. `~/.wezterm.lua` loads `tracker.lua`.

## Install / uninstall

    bash install.sh      # edits ~/.claude/settings.json (timestamped backup first)
    bash uninstall.sh

The `~/.wezterm.lua` change (package.path, `tracker.tab_dot`, `tracker.setup`) is edited by hand; the
pre-change copy is `~/.wezterm.lua.bak-*`. Restart Claude sessions after installing so they load the hooks.

## Tests

    sh tests/run.sh      # needs jq, git and luajit
