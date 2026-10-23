# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

wezterm-claude-kit: native tools for running several Claude Code sessions in WezTerm panes (POSIX sh, `jq`, WezTerm Lua). It is installed into the user's live `~/.claude/settings.json` and `~/.wezterm.lua`, so changes here affect their real sessions immediately. Design spec and plan are in `docs/`.

## Commands

```sh
sh tests/run.sh                    # all shell tests plus luajit tests; exits non-zero on any failure
sh tests/track_state_test.sh       # one shell test file (statusline_test.sh, install_test.sh likewise)
luajit tests/logic_test.lua        # pure Lua logic tests
bash install.sh [--home DIR]       # hooks + status line into DIR/.claude/settings.json (backup first, idempotent)
bash uninstall.sh [--home DIR]
```

Needs `jq`, `git` and `luajit` (no `lua`, `bats` or `shellcheck`). A test file runs all its tests; there is no per-test selector, so to isolate one, temporarily trim the `for t in ...` list at the bottom of the file. Test files are plain sh built on `tests/lib.sh` (`assert_eq`, `assert_contains`, `new_tmp`, `strip_ansi`, `finish`).

## Architecture

Claude hooks write per-pane state files, and two readers render them. No daemon.

- `hooks/track-state.sh`: registered for ten hook events. Maps the event to `working`, `needs-you` or `idle` and writes `$SESSION_TRACKER_STATE_DIR/<WEZTERM_PANE>.json` (default `~/.claude/state/panes`). Also plays the done sound on `Stop`. Subagent events (`agent_id` present) are dropped, except `PermissionRequest` and `Notification`, which still mean the pane needs the user.
- `statusline/statusline-command.sh`: model glyph, repo, branch, `±N` changed lines, `↑N` ahead and context percent. Git data comes from live git via `lib/git-info.sh`, which the hook also sources. It does not read the state `.json` files, only `<WEZTERM_PANE>.pos` (pane number badge, written by `tracker.lua`). It fits itself to the pane width, found by walking up to the first parent process with a tty and running `stty`.
- `wezterm/tracker.lua` + `wezterm/logic.lua`: tracker is the WezTerm glue (reads state files, tab view, right status, `gui-startup` wipe); logic holds the pure functions (`worst`, `counts`, `summary`, `usage_text`, `tab_label`, `right_status`) so they run under plain luajit.
- Account usage (5h/7d) is not computed here: `~/.claude/fetch-usage.sh` (outside this repo) writes `/tmp/.claude_usage_cache`, and `tracker.lua` reads it.
- `~/.wezterm.lua` is edited by hand and not stored in this repo. Its `format-tab-title` handler calls `tracker.tab_view`, `tracker.dot` and picks the rose "needs you" tab colors; `tracker.setup(config)` registers the right-status and startup handlers.

## Rules that are easy to break

- Hooks must always exit 0 and never print to stdout or block (Claude waits on them). Failure must mean "shows nothing".
- A Lua error inside `format-tab-title` breaks the whole tab bar. Wrap new runtime code in `pcall`, and keep the `pcall(require, "tracker")` stub in `~/.wezterm.lua`.
- The status line runs on every refresh, so keep its git calls few and never `git fetch`.
- Tests must not play real sounds or post real notices: `tests/track_state_test.sh` exports `SESSION_TRACKER_SOUND=""`, `SESSION_TRACKER_SOUND_NEEDS=""` and `SESSION_TRACKER_NOTIFY=""`. Other test-facing env overrides: `SESSION_TRACKER_STATE_DIR`, `SESSION_TRACKER_PLAYER`, `SESSION_TRACKER_NOTIFIER`, `SESSION_TRACKER_FRONTMOST` (command printing the frontmost app name), `SESSION_TRACKER_USAGE_CACHE`, `SESSION_TRACKER_COLS` (status line width).
- `install.sh` installs hook commands guarded with `if [ -f ... ]` so a moved folder degrades quietly. `uninstall.sh` finds its entries by the substring `wezterm-claude-kit/hooks/track-state.sh`, so keep that path segment stable.

## WezTerm facts (build 20240203) learned the hard way

- `$WEZTERM_PANE` equals `pane:pane_id()`, which is why files are keyed by it. Pane ids restart with the mux, hence the state-dir wipe on `gui-startup` (the handler must not spawn a window itself).
- `wezterm.read_dir` failed inside `format-tab-title`, so pane files are opened by id with `io.open`. `wezterm.mux.get_tab(id):panes()` works there.
- WezTerm has no per-pane padding and no divider thickness setting; `window_padding` only pads the window edge.
- The right status is clipped from the left in narrow windows, so the most important part (counts) goes last.
