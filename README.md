# Session tracker

Shows the state of every Claude Code session running in WezTerm panes.

- **Hooks** (`hooks/track-state.sh`) write one file per pane, `~/.claude/state/panes/<WEZTERM_PANE>.json`:
  `{"state","repo","branch","cwd","session_id","ts"}`. States: `working`, `needs-you`, `idle`.
- **Status line** (`statusline/statusline-command.sh`): `model | dot repo branch | +A -D ↑N base | ctx bar`; the ctx bar is a thin 10-cell line in half-cell steps, green under 50%, amber under 80%, red above, followed by percent and used tokens.
- **WezTerm** (`wezterm/`): each tab shows `[n] repo:branch` of its focused pane with a state dot (worst state
  among the tab's panes). A tab with a pane that needs you turns rose. The right of the tab bar shows the counts
  plus 5h/7d usage. `~/.wezterm.lua` loads `tracker.lua`.

## Install / uninstall

    bash install.sh      # edits ~/.claude/settings.json (timestamped backup first)
    bash uninstall.sh

The `~/.wezterm.lua` change (package.path, `tracker.tab_view`, `tracker.dot`, `tracker.setup`) is edited by hand; the
pre-change copy is `~/.wezterm.lua.bak-*`. Restart Claude sessions after installing so they load the hooks.

## Tests

    sh tests/run.sh      # needs jq, git and luajit
