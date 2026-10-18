# Session tracker for parallel Claude sessions in WezTerm - design

Date: 2026-10-19
Status: draft for approval

## Intent and why

The user runs 3-4 tasks at once. Within one repo, each task lives in its own git worktree and is merged to the main branch when done. Each task is a Claude Code session in a WezTerm pane. Typical layout: 4 tabs side by side, each tab a 2x2 grid with Claude in all four panes.

The pain, in the user's words: "there is too much thing going on and sometime I just lost tracks". Confirmed to mean all three of: which session is doing what, which one is waiting on the user, and where each branch stands.

This project (`~/Projects/my_proj`) is meant as a home for workflow research, ideas and small tools. The session tracker is the first tool. The research side starts empty: the user declined every proposed follow-up idea for now.

Why now: the user already has partial plumbing (hooks, a custom status line, a custom tab title) and previously installed herdr and Orca hooks, then dropped both tools as too heavy.

## What exists today (verified by reading the files)

- `~/.wezterm.lua`: rose-pine, JetBrains Mono 15, tab bar at top, non-fancy. A `format-tab-title` handler renders `[n] <pane title>`. No status handler. Tab bar hidden when only one tab.
- `~/.claude/statusline-command.sh`: one line with model, folder, branch, staged/unstaged counts, 5h and 7d usage bars, context bar. Usage comes from `/tmp/.claude_usage_cache`, written by `~/.claude/fetch-usage.sh` (called from `PreToolUse` and `Stop` hooks). The usage bars are identical in every pane.
- `~/.claude/settings.json` hooks already registered: `PreToolUse`, `PostToolUse`, `PostToolUseFailure`, `PermissionRequest`, `Stop`, `StopFailure`, `UserPromptSubmit`, `SessionStart`. Settings also have `inputNeededNotifEnabled` and `agentPushNotifEnabled` on.
- Leftovers: hooks calling `~/.claude/hooks/herdr-agent-state.sh` and `~/.orca/agent-hooks/claude-hook.sh`. Neither tool is installed, so both are no-ops today.

## Goals

1. At a glance, from any pane, see for every session: which repo and branch/worktree, whether it is working, needs the user, or is idle/done, and how far its branch is from main.
2. Tab titles carry the same information in aggregate, so trouble shows without opening the tab.
3. Account-wide usage (5h, 7d) is shown once, not in every pane.
4. Fully native: Claude hooks, a shell status line, WezTerm Lua. The user chose this explicitly.

## Non-goals and anti-goals

- No daemon, background service, TUI, or new terminal multiplexer. The user rejected herdr and Orca as "heavy".
- Not a session launcher, merge tool or worktree manager. Those ideas were offered and declined.
- Anti-goal: anything that can break or slow the terminal, or needs babysitting. A failure in the tracker must degrade to "shows nothing", never to a broken pane or blocked Claude turn.

## Decisions the user made

- Pane status line: option "B (standard)": state dot, repo, branch, uncommitted diff size, commits ahead of main, context bar. Format in the approved mockup: `● api feat/auth-token | +140 -32 ↑3 main | ctx ▓▓▓░░░░ 41%`.
- Layout assumption: 4 tabs horizontal, 2x2 grid per tab, Claude in every pane. The user liked the grid.
- Usage bars (4h/4d style, as in the current status line) leave the panes and appear once in WezTerm.
- Counts like "1 waiting, 2 working" appear once in WezTerm.
- Tab title carries a state dot.
- Native only (see non-goals).

## Proposed design (Claude's calls unless marked as user's)

These are my proposals; the user has not seen the file-based mechanism in detail.

**State source.** The hooks already registered (`UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `PermissionRequest`, `Stop`, `StopFailure`, `SessionStart`) also write a small per-pane state file, keyed by `$WEZTERM_PANE`. Content: state, repo, branch, worktree path, session id, timestamp. Suggested location under `~/.claude/state/`. Suggested mapping (my call, builder may refine):
- `UserPromptSubmit`, `PreToolUse`, `PostToolUse` -> working
- `PermissionRequest` (and any question-to-user event) -> needs-you
- `Stop` -> idle/done
- `StopFailure` -> needs-you
- `SessionStart` -> idle; a session-end event or stale check removes the file.

**Consumers.**
- Status line script reads its own pane's state file plus git (branch, diff size, ahead-of-main) and drops the usage bars.
- WezTerm Lua: `format-tab-title` colors a dot per tab using the worst state among that tab's panes (needs-you beats working beats idle). A `update-right-status` handler renders global counts and the 5h/7d usage read from the existing cache file. Correction to an earlier mockup: WezTerm has no separate bottom status bar, only the tab bar, so counts and usage go on the right side of the tab bar (the tab bar can also be moved to the bottom if the user prefers; the user has not been asked).
- Pane id from the hook environment must match the pane id WezTerm Lua sees; the builder must verify this.

**Robustness (anti-goal driven).** Hooks and status line must never fail loudly or add noticeable latency: write atomically, swallow errors, exit 0. Lua ignores state files for panes that no longer exist.

**Existing leftovers.** The no-op herdr and Orca hook entries are not touched by this design. Whether to remove them is left to the user (not asked yet).

## Constraints

- macOS, zsh, WezTerm, Claude Code with `statusLine` command and hooks in `~/.claude/settings.json`.
- Global rules from the user's CLAUDE.md apply: never commit or push without being told; plain dash, no em dash in text; feature branches and worktrees for repo work.
- `~/.claude/skills` is a symlink into this project (`my-grimoire/skills`), so be careful not to disturb that folder.
- `~/Projects/my_proj` is not a git repo today.

## Left to the builder

- Exact file format, file location, naming and atomic-write method of the state files.
- How to compute ahead-of-main cheaply (status line runs often) and how to find the main branch name per repo.
- Colors, glyphs, truncation, and final status-line wording, within the approved option B.
- How to clean up stale state files.
- Where scripts and Lua live inside this project and how they are installed or symlinked into `~/.claude` and `~/.wezterm.lua`.
- Testing approach, including how to simulate several panes.

## Added after builder review

Verified: in a live Claude pane, `$WEZTERM_PANE` was `0`, and `wezterm cli list` reported that same pane with `PANEID 0`. So keying state files by `$WEZTERM_PANE` works. Pane ids restart after a WezTerm restart, so Lua must ignore files for pane ids that are not live, and `SessionStart` overwrites any old file for its pane id (my call).

User decision on install: edit the live `~/.claude/settings.json` and `~/.wezterm.lua` directly, taking a timestamped backup of each first. Hooks and Lua must still degrade to "shows nothing" on failure.

More of my calls:

6. Add the `Notification` hook event (permission prompt, idle prompt) to the state mapping as needs-you. `settings.json` already has an empty `Notification` array. A turn that ends with a question to the user still looks like `Stop` (idle); accepted limit unless `Notification` covers it.
7. Ahead-of-main: compare `HEAD` to `origin/<default branch>` if it exists, else local `main` or `master`. No `git fetch` from the status line. Show ahead only, not behind.
8. Panes without a state file (shells, editors) show no dot and do not count. A tab with no Claude panes shows no dot.
9. Tab title keeps `[n] <pane title>` and gains a state dot as prefix.
10. If the usage cache is missing or older than 15 minutes, the right status shows `n/a` for usage instead of the old number.
11. Hook order in `settings.json` does not matter for this design. The tracker's hooks are independent of the herdr and Orca no-ops.

## My calls to check

1. State mapping from hook events to three states (above).
2. Counts and usage go in the tab bar's right side, not a bottom bar.
3. Design document location: first `docs/superpowers/specs/` at the project root, later moved with the plan into `tools/session-tracker/docs/` at the user's request (the folder is not a git repo).
4. Leftover herdr/Orca hooks are left alone.
5. Only three states (working, needs-you, idle/done). The earlier mockups also showed "mergeable"; it is dropped for now.
