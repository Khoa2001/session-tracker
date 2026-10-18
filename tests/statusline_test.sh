#!/bin/sh
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/lib.sh"
SL="$HERE/../statusline/statusline-command.sh"

RED='38;2;235;111;146m●'
YELLOW='38;2;246;193;119m●'
GREEN='38;2;152;195;121m●'

# render DIR  -> raw status line (with ANSI) using $SD and pane 7 unless NOPANE
render() {
  json=$(printf '{"model":{"display_name":"Sonnet 5.5","id":"claude-sonnet-5-5"},"workspace":{"current_dir":"%s"},"context_window":{"used_percentage":41.2,"context_window_size":1000000,"current_usage":{"input_tokens":1000,"output_tokens":100,"cache_read_input_tokens":40000,"cache_creation_input_tokens":0}}}' "$1")
  if [ -n "${NOPANE:-}" ]; then
    printf '%s' "$json" | env -u WEZTERM_PANE SESSION_TRACKER_STATE_DIR="${SD:-/nonexistent}" sh "$SL"
  else
    printf '%s' "$json" | WEZTERM_PANE=7 SESSION_TRACKER_STATE_DIR="${SD:-/nonexistent}" sh "$SL"
  fi
}

plain() { render "$1" | strip_ansi; }

# make_clone ROOT: ROOT/origin (main) and ROOT/api on feat/auth-token,
# 2 commits ahead of origin/main, with 3 added and 1 deleted uncommitted lines.
make_clone() {
  git init -q -b main "$1/origin"
  printf 'l1\nl2\nl3\n' > "$1/origin/f"
  git -C "$1/origin" add f
  git -C "$1/origin" commit -q -m init
  git clone -q "$1/origin" "$1/api"
  git -C "$1/api" checkout -q -b feat/auth-token
  git -C "$1/api" commit -q --allow-empty -m c1
  git -C "$1/api" commit -q --allow-empty -m c2
  printf 'l2\nl3\nn1\nn2\nn3\n' > "$1/api/f"
}

test_shows_repo_branch_diff_ahead() {
  root=$(new_tmp); make_clone "$root"
  out=$(plain "$root/api")
  assert_contains "repo" "$out" "api"
  assert_contains "branch" "$out" "feat/auth-token"
  assert_contains "diff" "$out" "+3 -1"
  assert_contains "ahead" "$out" "↑2 origin/main"
  assert_contains "model" "$out" "Sonnet 5.5"
  assert_contains "ctx" "$out" "41%"
}

test_dot_follows_state_file() {
  root=$(new_tmp); make_clone "$root"; SD=$(new_tmp)
  for pair in "needs-you:$RED" "working:$YELLOW" "idle:$GREEN"; do
    st=${pair%%:*}; code=${pair#*:}
    printf '{"state":"%s"}' "$st" > "$SD/7.json"
    assert_contains "dot color for $st" "$(render "$root/api")" "$code"
  done
}

test_no_state_file_no_dot() {
  root=$(new_tmp); make_clone "$root"; SD=$(new_tmp)
  assert_not_contains "no pane" "$(NOPANE=1 plain "$root/api")" "●"
  assert_not_contains "no file" "$(plain "$root/api")" "●"
}

test_corrupt_state_file_no_dot_no_error() {
  root=$(new_tmp); make_clone "$root"; SD=$(new_tmp)
  printf '{bad' > "$SD/7.json"
  out=$(render "$root/api" 2>"$SD/err"); rc=$?
  assert_eq "exit 0" 0 "$rc"
  assert_not_contains "no dot" "$out" "●"
  assert_eq "empty stderr" "" "$(cat "$SD/err")"
  : > "$SD/7.json"
  assert_not_contains "empty file no dot" "$(render "$root/api")" "●"
}

test_no_usage_bars() {
  root=$(new_tmp); make_clone "$root"
  out=$(plain "$root/api")
  assert_not_contains "no 5h" "$out" "5h"
  assert_not_contains "no 7d" "$out" "7d"
  assert_eq "exactly one percent" 1 "$(printf '%s' "$out" | tr -cd '%' | wc -c | tr -d ' ')"
}

test_non_git_dir_omits_git_part() {
  d=$(new_tmp)
  out=$(plain "$d"); rc=$?
  assert_eq "exit 0" 0 "$rc"
  assert_contains "model" "$out" "Sonnet 5.5"
  assert_contains "ctx" "$out" "ctx"
  assert_not_contains "no ahead" "$out" "↑"
  assert_not_contains "no diff" "$out" "+0"
}

test_clean_tree_omits_diff() {
  root=$(new_tmp); make_clone "$root"
  git -C "$root/api" checkout -q -- f
  out=$(plain "$root/api")
  assert_not_contains "no +0 -0" "$out" "+0 -0"
  assert_contains "ahead still shown" "$out" "↑2"
}

test_detached_head_no_error() {
  root=$(new_tmp); make_clone "$root"
  git -C "$root/api" checkout -q --detach HEAD~1
  sha=$(git -C "$root/api" rev-parse --short HEAD)
  out=$(plain "$root/api" 2>&1); rc=$?
  assert_eq "exit 0" 0 "$rc"
  assert_contains "short sha shown" "$out" "$sha"
}

test_no_origin_no_main_omits_ahead() {
  d=$(new_tmp)
  git init -q -b topic "$d/solo"
  git -C "$d/solo" commit -q --allow-empty -m i
  out=$(plain "$d/solo")
  assert_contains "branch" "$out" "topic"
  assert_not_contains "no ahead" "$out" "↑"
}

test_worktree_shows_main_repo_name() {
  root=$(new_tmp); make_clone "$root"
  git -C "$root/api" worktree add -q -b feat/y "$root/wt2"
  out=$(plain "$root/wt2")
  assert_contains "main repo name" "$out" "api"
  assert_contains "worktree branch" "$out" "feat/y"
  assert_not_contains "not dir name" "$out" "wt2"
}

for t in test_shows_repo_branch_diff_ahead test_dot_follows_state_file \
  test_no_state_file_no_dot test_corrupt_state_file_no_dot_no_error \
  test_no_usage_bars test_non_git_dir_omits_git_part test_clean_tree_omits_diff \
  test_detached_head_no_error test_no_origin_no_main_omits_ahead \
  test_worktree_shows_main_repo_name; do
  ( "$t" )
done
finish
