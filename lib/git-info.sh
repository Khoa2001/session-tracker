#!/bin/sh
# Git helpers shared by the state hook and the status line. Source this file.
# Every function prints nothing (and returns 0) outside a repo or on any error.

# Basename of the MAIN worktree root, so a linked worktree reports the main repo.
git_repo_name() {
  [ -n "$1" ] || return 0
  common=$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 0
  [ -n "$common" ] || return 0
  basename "$(dirname "$common")"
}

# Current branch, short SHA when detached.
git_branch() {
  [ -n "$1" ] || return 0
  git -C "$1" symbolic-ref --short -q HEAD 2>/dev/null \
    || git -C "$1" rev-parse --short HEAD 2>/dev/null \
    || true
}

# Ref to measure "ahead" against: origin's default branch, else origin/main,
# origin/master, main, master. Never fetches.
git_base_ref() {
  [ -n "$1" ] || return 0
  ref=$(git -C "$1" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null)
  if [ -n "$ref" ]; then echo "$ref"; return 0; fi
  for c in origin/main origin/master main master; do
    if git -C "$1" rev-parse -q --verify "$c^{commit}" >/dev/null 2>&1; then
      echo "$c"; return 0
    fi
  done
}

# Commits in HEAD that are not in <base>.
git_ahead() {
  [ -n "$1" ] && [ -n "$2" ] || return 0
  git -C "$1" rev-list --count "$2..HEAD" 2>/dev/null
}

# "<added> <deleted>" over staged plus unstaged changes to tracked files.
git_diff_stat() {
  [ -n "$1" ] || { echo "0 0"; return 0; }
  git -C "$1" diff HEAD --numstat 2>/dev/null \
    | awk '{a+=$1; d+=$2} END{printf "%d %d\n", a, d}'
}
