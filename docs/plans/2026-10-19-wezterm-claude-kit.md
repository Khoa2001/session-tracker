# Session Tracker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show, for every Claude session in WezTerm, its state (working, needs-you, idle), repo, branch and distance from main, with account usage shown once instead of in every pane.

**Architecture:** Claude hooks write one small JSON state file per WezTerm pane, keyed by `$WEZTERM_PANE`. A rewritten status line script reads its own pane's file plus live git info. A WezTerm Lua module reads all files to color a dot in each tab title and to render global counts and usage on the right of the tab bar. No daemon.

**Tech Stack:** POSIX sh, `jq`, `git`, WezTerm Lua (20240203 build), LuaJIT for pure-logic tests (`/opt/homebrew/bin/luajit`; no `lua`, `bats` or `shellcheck` installed).

**Spec:** `tools/wezterm-claude-kit/docs/specs/2026-10-19-wezterm-claude-kit-design.md`

## Global Constraints

- Native only: no daemon, background service, TUI or multiplexer.
- A tracker failure must degrade to "shows nothing", never break a pane, block a Claude turn, or add noticeable latency. Hooks exit 0 always; Lua never raises (a Lua error in `format-tab-title` breaks the tab bar).
- Three states only: `working`, `needs-you`, `idle`. No "mergeable".
- Pane status line is the approved option B: `● repo branch | +A -D ↑N base | ctx bar pct`. Usage bars are removed from it.
- Counts and 5h/7d usage go on the right side of the WezTerm tab bar (no separate bottom bar).
- Tab title keeps `[n] <pane title>` and gains a state dot as prefix.
- Never commit, push or `git init`. The user's rule is to commit only when told. Leave all work uncommitted. `~/Projects/my_proj` is not a git repo.
- Plain dash, no em dash, in all text and comments.
- Do not touch `~/Projects/my_proj/my-grimoire/` (`~/.claude/skills` symlinks into it).
- Live files `~/.claude/settings.json` and `~/.wezterm.lua` are edited directly (user decision), each after a timestamped backup.
- Leave the herdr and Orca hook entries untouched.
- All code lives under `tools/wezterm-claude-kit/` in this project.

## Review Focus

Each line has its test in the owning task.

1. Hook runs with no `WEZTERM_PANE` (Claude in another terminal): exit 0, no file, no output. (Task 1)
2. Subagent tool events (hook JSON has `agent_id`) arriving after `Stop` must not flip `idle` back to `working`. (Task 1)
3. cwd is not a git repo, is a detached HEAD, or has no `origin` and no `main`/`master`: status line shows no error and omits the missing segment. (Tasks 1, 2)
4. Empty, corrupt or half-written state file, or missing/stale usage cache: status line and Lua show nothing or `n/a`, never an error. (Tasks 2, 3, 4)
5. Pane ids restart after a WezTerm restart, so an old file could paint a dot on a plain shell pane. Mitigation: wipe the state dir on `gui-startup`, ignore files for non-live pane ids, `SessionStart` overwrites. (Tasks 1, 4)

---

### Task 1: State hook and shared git helpers

**Files:**
- Create: `tools/wezterm-claude-kit/lib/git-info.sh`
- Create: `tools/wezterm-claude-kit/hooks/track-state.sh`
- Create: `tools/wezterm-claude-kit/tests/lib.sh` (assert helpers: `assert_eq name expected actual`, `assert_contains`, `assert_not_contains`, `new_tmp` returning a fresh temp dir cleaned on exit)
- Create: `tools/wezterm-claude-kit/tests/run.sh` (runs every `tests/*_test.sh` and `luajit tests/*_test.lua`, exits non-zero on any failure)
- Test: `tools/wezterm-claude-kit/tests/track_state_test.sh`

**Interfaces:**
- Produces, `lib/git-info.sh` (POSIX sh, meant to be sourced):
  - `git_repo_name <dir>`: basename of the MAIN worktree root, derived from `git rev-parse --git-common-dir` (so a linked worktree reports the main repo name). Empty if not a repo.
  - `git_branch <dir>`: current branch, short SHA when detached, empty if not a repo.
- Produces, `hooks/track-state.sh`: stdin is Claude's hook JSON (`hook_event_name`, `session_id`, `cwd`, `notification_type`, optional `agent_id`). Env: `WEZTERM_PANE`, `SESSION_TRACKER_STATE_DIR` (default `$HOME/.claude/state/panes`). Writes `<dir>/<WEZTERM_PANE>.json` atomically (temp file + `mv`) containing `{"state":"working|needs-you|idle","repo":string,"branch":string,"cwd":string,"session_id":string,"ts":int epoch seconds}`.
- Event mapping: `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `PostToolUseFailure` -> `working`; `PermissionRequest`, `StopFailure` -> `needs-you`; `Notification` -> `needs-you` when `notification_type` is `permission_prompt` or `idle_prompt`, otherwise leave the file unchanged; `Stop`, `SessionStart` -> `idle`; `SessionEnd` -> delete the file.
- Rules: ignore events carrying `agent_id`; exit 0 and write nothing when `WEZTERM_PANE` is unset, stdin is not valid JSON, or the state dir is unwritable; on `SessionStart`, also delete files in the dir older than 7 days.

- [ ] **Step 1: Write failing tests in `tests/track_state_test.sh`**

Each test pipes a JSON fixture into the script with `WEZTERM_PANE=7` and a temp `SESSION_TRACKER_STATE_DIR`, then inspects `7.json` with `jq`. Test names and assertions:
  - `maps_working_events`: the four working events each yield `.state == "working"`.
  - `maps_needs_you_events`: `PermissionRequest`, `StopFailure`, `Notification` with `permission_prompt`, `Notification` with `idle_prompt` each yield `needs-you`.
  - `notification_other_type_keeps_state`: after `Stop`, `Notification` with `notification_type: "auth_success"` leaves `.state == "idle"`.
  - `stop_and_sessionstart_are_idle`.
  - `sessionend_removes_file`.
  - `subagent_event_ignored_after_stop`: `Stop`, then `PreToolUse` with `"agent_id":"a1"` -> still `idle`.
  - `no_wezterm_pane_is_noop`: `WEZTERM_PANE` unset -> exit 0, empty stdout, dir has no files.
  - `invalid_json_is_noop`: stdin `not json` -> exit 0, no file.
  - `unwritable_dir_exits_zero`: state dir is a regular file path -> exit 0.
  - `non_git_cwd_has_empty_repo_and_branch`: `.repo == ""`, `.branch == ""`, file still valid.
  - `worktree_reports_main_repo_and_own_branch`: temp repo `api` with a linked worktree on branch `feat/x` -> `.repo == "api"`, `.branch == "feat/x"`.
  - `sessionstart_prunes_files_older_than_7_days`: a file touched with `-t` 10 days ago is gone, a fresh other-pane file remains.
  - `output_is_always_valid_json`: `jq empty` passes after each event.

- [ ] **Step 2: Run to verify failure**

Run: `sh tools/wezterm-claude-kit/tests/run.sh`
Expected: FAIL (script does not exist).

- [ ] **Step 3: Implement `lib/git-info.sh` and `hooks/track-state.sh`**

Use one `jq` call to extract all hook fields. Build the state file with `jq -n --arg ...` so values are escaped. Wrap the whole body so any failure still exits 0.

- [ ] **Step 4: Run to verify pass**

Run: `sh tools/wezterm-claude-kit/tests/run.sh`
Expected: all `track_state_test.sh` tests PASS.

---

### Task 2: Status line (option B)

**Files:**
- Create: `tools/wezterm-claude-kit/statusline/statusline-command.sh`
- Modify: `tools/wezterm-claude-kit/lib/git-info.sh` (add the functions below)
- Test: `tools/wezterm-claude-kit/tests/statusline_test.sh`

**Interfaces:**
- Consumes: `git_repo_name`, `git_branch` from Task 1; state file format from Task 1.
- Produces, added to `lib/git-info.sh`:
  - `git_base_ref <dir>`: `origin/<default>` if `refs/remotes/origin/HEAD` or `origin/main` or `origin/master` resolves, else local `main`, else local `master`, else empty. Never runs `git fetch`.
  - `git_ahead <dir> <base>`: integer count of `base..HEAD`.
  - `git_diff_stat <dir>`: prints `<added> <deleted>` summed over `git diff HEAD --numstat` (staged plus unstaged, tracked files).
- Produces, `statusline-command.sh`: reads Claude status JSON on stdin (`.model.display_name`, `.model.id`, `.workspace.current_dir`, `.context_window.used_percentage`, `.context_window.current_usage`, `.context_window.context_window_size`). Env: `WEZTERM_PANE`, `SESSION_TRACKER_STATE_DIR`. Prints one line: `model │ ● repo branch │ +A -D ↑N base │ ctx bar pct (usedk/totalk)`.
- Rules: keep the existing script's model colors, `bar()` helper and `│` separators, and keep the model name as first segment (my call: it is per-session information). Remove the 5h/7d usage bars and the `fetch-usage.sh` fallback call. The dot color comes from the pane's state file (red `needs-you`, yellow `working`, green `idle`, colors the implementer's call); no state file or no `WEZTERM_PANE` means no dot. Repo and branch come from live git, not the state file. Omit the `+A -D` segment when both are 0, omit `↑N base` when base is empty or N is 0, omit the git part entirely outside a repo.

- [ ] **Step 1: Write failing tests in `tests/statusline_test.sh`**

Strip ANSI with `sed` before asserting. Fixtures: a temp `origin` repo with `main`, a clone `api` with a branch `feat/auth-token` that is 2 commits ahead and has 3 added and 1 deleted uncommitted lines. Tests:
  - `shows_repo_branch_diff_ahead`: output contains `api`, `feat/auth-token`, `+3 -1`, `↑2 origin/main`.
  - `dot_follows_state_file`: state `needs-you` -> output contains `●` and the red SGR code; `working` -> yellow code; `idle` -> green code.
  - `no_state_file_no_dot`: no `WEZTERM_PANE` -> output contains no `●`.
  - `corrupt_state_file_no_dot_no_error`: state file `{bad` -> no `●`, exit 0, empty stderr.
  - `no_usage_bars`: output contains neither `5h` nor `7d`, and exactly one `%`.
  - `non_git_dir_omits_git_part`: cwd is a plain temp dir -> output has the model and ctx segments only, exit 0.
  - `detached_head_no_error`: checkout a SHA -> branch shows short SHA, exit 0.
  - `no_origin_no_main_omits_ahead`: repo on branch `topic` with no `main`/`master`/origin -> no `↑`.
  - `worktree_shows_main_repo_name`.

- [ ] **Step 2: Run to verify failure**

Run: `sh tools/wezterm-claude-kit/tests/run.sh`
Expected: statusline tests FAIL.

- [ ] **Step 3: Implement the new git helpers and the script**

Start from `~/.claude/statusline-command.sh` (current behavior listed in the spec) and edit it down. Keep each git helper to one `git` call where possible; this script runs often.

- [ ] **Step 4: Run to verify pass**

Run: `sh tools/wezterm-claude-kit/tests/run.sh`
Expected: all tests PASS.

- [ ] **Step 5: Visual check against the approved mockup**

Run: `echo '<fixture status json>' | WEZTERM_PANE=<live pane> bash tools/wezterm-claude-kit/statusline/statusline-command.sh` in a live WezTerm pane inside a real worktree.
Expected: one line matching mockup B: dot, repo, branch, `+A -D`, `↑N base`, ctx bar. No usage bars.

---

### Task 3: Pure Lua logic

**Files:**
- Create: `tools/wezterm-claude-kit/wezterm/logic.lua` (no `require("wezterm")`, so it runs under LuaJIT)
- Test: `tools/wezterm-claude-kit/tests/logic_test.lua`

**Interfaces:**
- Produces, `logic.lua` returns a table `M`:
  - `M.worst(states: string[]) -> string|nil`: `needs-you` beats `working` beats `idle`; nil for an empty list or only unknown values.
  - `M.counts(states: string[]) -> {["needs-you"]=int, working=int, idle=int}`.
  - `M.summary(counts) -> string`: e.g. `1 waiting · 2 working · 1 idle`, zero counts omitted, empty string when all are zero. (Wording is the implementer's call, but the test pins the chosen wording.)
  - `M.usage_text(lines: string[]|nil, age_seconds: number|nil, now_epoch: number) -> string`: input is the 4 lines of `/tmp/.claude_usage_cache` (5h pct, 7d pct, 5h reset ISO, 7d reset ISO). Output like `4h 37m 2% │ 4d 12h 51%` (reset countdown plus pct, as in the approved mockup). Returns `usage n/a` when `lines` is nil, has fewer than 4 entries, or `age_seconds` is nil or above 900. If a reset ISO string does not parse, fall back to the labels `5h` and `7d` for that segment.

- [ ] **Step 1: Write failing tests in `tests/logic_test.lua`**

Plain `assert` with a small `eq(name, got, want)` helper that prints failures and exits 1. Tests:
  - `worst` of `{"idle","working"}` is `working`; of `{"idle","needs-you","working"}` is `needs-you`; of `{}` is nil; of `{"bogus"}` is nil.
  - `counts` of `{"working","working","idle","needs-you"}` equals `{["needs-you"]=1, working=2, idle=1}`.
  - `summary` of those counts equals the exact chosen string; all-zero gives `""`.
  - `usage_text` with lines `{"2","51","2026-10-19T04:37:00+00:00","2026-10-23T12:00:00+00:00"}`, `now_epoch` set to 2026-10-19T00:00:00Z, age 60 gives `4h 37m 2% │ 4d 12h 51%`.
  - `usage_text` with age 901 gives `usage n/a`; with nil lines gives `usage n/a`; with 3 lines gives `usage n/a`.
  - `usage_text` with a garbage reset string gives `5h 2%` for that segment.
  - A reset time in the past gives `now` as the countdown (same as the current script's `compute_delta`).

- [ ] **Step 2: Run to verify failure**

Run: `luajit tools/wezterm-claude-kit/tests/logic_test.lua`
Expected: FAIL (module missing).

- [ ] **Step 3: Implement `logic.lua`**

Parse ISO timestamps with a pattern and compute epoch with a days-from-civil formula so the result does not depend on the machine time zone.

- [ ] **Step 4: Run to verify pass**

Run: `sh tools/wezterm-claude-kit/tests/run.sh`
Expected: all shell and Lua tests PASS.

---

### Task 4: WezTerm glue and live `~/.wezterm.lua`

**Files:**
- Create: `tools/wezterm-claude-kit/wezterm/tracker.lua`
- Modify (live, after backup): `/Users/khoamai/.wezterm.lua`
- Backup first: `cp ~/.wezterm.lua ~/.wezterm.lua.bak-$(date +%Y%m%d-%H%M%S)`

**Interfaces:**
- Consumes: `logic.lua` from Task 3; state file format from Task 1.
- Produces, `tracker.lua` returns `M`:
  - `M.read_states(dir: string, live_pane_ids: table<number,true>) -> table<number, {state:string, repo:string, branch:string}>`: reads `<id>.json` for live ids only, using `wezterm.read_dir`, `io.open` and `wezterm.json_parse`, every call under `pcall`. Returns `{}` on any error and skips a corrupt file without raising.
  - `M.tab_dot(tab) -> FormatItem[]`: the dot (colored by `logic.worst` over that tab's Claude panes) followed by a space, or `{}` when no pane in the tab has a state file. Pure of side effects; never raises.
  - `M.setup(config)`: registers `update-right-status` (counts via `logic.summary` plus `logic.usage_text` from `$SESSION_TRACKER_USAGE_CACHE` or `/tmp/.claude_usage_cache`, with file age from its mtime) and a `gui-startup` handler that deletes all `*.json` in the state dir.
- State dir: `$SESSION_TRACKER_STATE_DIR` or `$HOME/.claude/state/panes`. Dot colors are the implementer's call within red/yellow/green and must read well on the Nord (base16) palette already in `~/.wezterm.lua`.

- [ ] **Step 1: Spike three WezTerm API facts before writing code (20240203 build)**

In a scratch config under the scratchpad directory, log with `wezterm.log_info` and read `~/.local/share/wezterm` logs, or use `wezterm.GLOBAL`, to confirm: (a) how to list a tab's panes from inside `format-tab-title` (try `wezterm.mux.get_tab(tab.tab_id):panes()`; if that fails, compute a `tab_id -> pane_ids` map in `update-status` and cache it in `wezterm.GLOBAL`); (b) that `pane:pane_id()` equals the `$WEZTERM_PANE` value; (c) that `wezterm.json_parse`, `wezterm.read_dir` and `os.getenv` work in that build. Write the working approach as a comment at the top of `tracker.lua`.
Expected: all three confirmed, approach recorded. If (a) has no workable path, stop and report to the user.

- [ ] **Step 2: Implement `tracker.lua`**

Cache `read_states` results for about one second so a burst of tab redraws does not re-read the directory for every tab.

- [ ] **Step 3: Edit `~/.wezterm.lua` directly (after the backup)**

Make three edits: add the module directory to `package.path` as an absolute path to `.../my_proj/tools/wezterm-claude-kit/wezterm/?.lua` and `require("tracker")`; in the existing `format-tab-title` handler, prepend `tracker.tab_dot(tab)` items before the `[n] title` text; call `tracker.setup(config)` before `return config`. Keep everything else byte-identical.

- [ ] **Step 4: Verify the config loads**

Run: `wezterm --config-file ~/.wezterm.lua show-keys > /dev/null`
Expected: exits 0 with no Lua error output. Then reload the running config (`Cmd+Ctrl+R` or save) and confirm the tab bar still renders.

- [ ] **Step 5: Simulate states and look at the real window**

For each live pane id from `wezterm cli list`, pipe `{"hook_event_name":"...","session_id":"s","cwd":"<path>"}` into `hooks/track-state.sh` with `WEZTERM_PANE=<id>`, covering one `needs-you`, one `working` and one `idle` pane, plus one plain shell pane with no file.
Expected: the tab dot shows the worst state, the right side of the tab bar shows `1 waiting · 1 working · 1 idle` and usage, and the shell pane contributes nothing. Compare spacing and colors against the approved mockup; the user is pixel-picky, so report anything off.

---

### Task 5: Installer, live rollout and end-to-end check

**Files:**
- Create: `tools/wezterm-claude-kit/install.sh`
- Create: `tools/wezterm-claude-kit/uninstall.sh`
- Create: `tools/wezterm-claude-kit/README.md` (what it does, the state file format, install and uninstall, how to run tests; short)
- Test: `tools/wezterm-claude-kit/tests/install_test.sh`
- Modify (live, via the script, after its own backup): `/Users/khoamai/.claude/settings.json`

**Interfaces:**
- Consumes: `hooks/track-state.sh` (Task 1), `statusline/statusline-command.sh` (Task 2).
- Produces, `install.sh [--home DIR]` (default `$HOME`): copies `settings.json` to `settings.json.bak-YYYYmmdd-HHMMSS`, then with `jq`: for each of `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `PostToolUseFailure`, `PermissionRequest`, `Notification`, `Stop`, `StopFailure`, `SessionStart`, `SessionEnd` appends `{"matcher":"*","hooks":[{"type":"command","command":"bash <abs path>/hooks/track-state.sh","timeout":5}]}` unless an entry with that exact command already exists; sets `statusLine.command` to `bash <abs path>/statusline/statusline-command.sh`. Existing hooks (including herdr and Orca) are preserved and keep their order. Idempotent. Creates `~/.claude/state/panes`.
- Produces, `uninstall.sh [--home DIR]`: backs up, removes entries whose command contains `wezterm-claude-kit/hooks/track-state.sh`, restores `statusLine.command` to `bash ~/.claude/statusline-command.sh`.
- The `~/.wezterm.lua` change is Task 4's manual edit, not scripted.

- [ ] **Step 1: Write failing tests in `tests/install_test.sh`**

Use a temp `--home` seeded with a copy of the real `settings.json` structure (herdr and Orca style hook entries, existing `statusLine`). Tests:
  - `install_adds_all_ten_events`: each event contains our command exactly once.
  - `install_is_idempotent`: running twice leaves the same file (compare `jq -S`).
  - `install_preserves_existing_hooks_and_order`: original entries unchanged and still first.
  - `install_sets_statusline`.
  - `install_creates_backup`: one `settings.json.bak-*` file exists and equals the original.
  - `install_output_is_valid_json`.
  - `uninstall_removes_only_ours_and_restores_statusline`.
  - `missing_settings_file_fails_cleanly`: non-zero exit and a message, no partial file.

- [ ] **Step 2: Run to verify failure**

Run: `sh tools/wezterm-claude-kit/tests/run.sh`
Expected: install tests FAIL.

- [ ] **Step 3: Implement `install.sh` and `uninstall.sh`**

Write the merged JSON to a temp file, validate with `jq empty`, then `mv` over the original so a failure never leaves a half-written `settings.json`.

- [ ] **Step 4: Run to verify pass**

Run: `sh tools/wezterm-claude-kit/tests/run.sh`
Expected: all shell and Lua tests PASS.

- [ ] **Step 5: Install for real**

Run: `bash tools/wezterm-claude-kit/install.sh`
Expected: backup file printed, `jq empty ~/.claude/settings.json` passes, `jq '.hooks.Stop | length' ~/.claude/settings.json` shows our entry added and the originals kept. New Claude sessions pick up hooks; existing sessions need a restart.

- [ ] **Step 6: End-to-end in the real window**

Restart Claude in 4 panes of one tab (2x2 grid, ideally in real worktrees of one repo) and run a prompt in each.
Expected, checked by the user's eye: each pane's status line shows `● repo branch │ +A -D ↑N base │ ctx` with no usage bars; the tab dot goes yellow while any pane works and red when one asks for permission or finishes a turn with `Notification`; the right of the tab bar shows counts and `4h ... │ 4d ...` usage once; closing a Claude pane removes its count; restarting WezTerm leaves no stale dots on plain shell panes.

- [ ] **Step 7: Report**

List what the user must check by eye (spacing, colors, truncation in a narrow tab), and any deviation from the spec. Do not commit.
