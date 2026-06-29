# git.sh — helper functions for the three common "get back in sync" git moves:
#   pull, soft/mixed reset, and hard reset.
#
# These wrap plain git so the destructive ones are explicit about what they will
# throw away and ask before doing it (unless you force past the prompt). They are
# autoloaded — source this file (it loads automatically) then call e.g.
# `git-pull` or `git-hard-reset`.
#
# Every function refuses to run outside a git work tree, so a stray invocation in
# the wrong directory is a no-op rather than a surprise.

# ---------------------------------------------------------------------------
# Internal: succeed only when run inside a git work tree, else warn + return 1.
# Not meant to be called directly; the public functions guard with it.
# ---------------------------------------------------------------------------
_git-require-repo() {
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "${1:-git-helper}: not inside a git work tree" >&2
    return 1
  fi
}

# ---------------------------------------------------------------------------
# Internal: echo the current branch name (empty on detached HEAD).
# ---------------------------------------------------------------------------
_git-current-branch() {
  git symbolic-ref --quiet --short HEAD 2>/dev/null
}

# ---------------------------------------------------------------------------
# Pull the current branch, fast-forward only by default.
#   git-pull [remote] [branch] [extra git-pull flags...]
#
#   remote   defaults to the current branch's upstream remote, else "origin".
#   branch   defaults to the current branch.
#
# Uses --ff-only so a pull never silently creates a merge commit; if the branch
# has diverged it stops and tells you, leaving you to rebase or merge yourself.
# Set GIT_PULL_REBASE=1 to pull with --rebase instead.
#
# Examples:
#   git-pull                  # ff-only from upstream
#   git-pull origin main
#   GIT_PULL_REBASE=1 git-pull
# ---------------------------------------------------------------------------
git-pull() {
  _git-require-repo "git-pull" || return 1

  local remote="${1:-}" branch="${2:-}"
  [ -n "$remote" ] && shift
  [ -n "$branch" ] && shift

  local mode="--ff-only"
  [ "${GIT_PULL_REBASE:-}" = "1" ] && mode="--rebase"

  if [ -n "$remote" ] && [ -n "$branch" ]; then
    echo "git-pull: git pull $mode $remote $branch" >&2
    git pull "$mode" "$remote" "$branch" "$@"
  else
    echo "git-pull: git pull $mode (upstream)" >&2
    git pull "$mode" "$@"
  fi
}

# ---------------------------------------------------------------------------
# Reset the current branch to a target ref, keeping working-tree changes.
#   git-reset [ref] [extra git-reset flags...]   (default ref: HEAD)
#
# This is a --mixed reset: it moves the branch pointer and unstages files but
# does NOT touch the files on disk — your edits are preserved as unstaged
# changes. Safe to use for "uncommit the last commit but keep my work":
#   git-reset HEAD~1
# ---------------------------------------------------------------------------
git-reset() {
  _git-require-repo "git-reset" || return 1

  local ref="${1:-HEAD}"
  [ -n "${1:-}" ] && shift

  echo "git-reset: git reset --mixed $ref (working tree preserved)" >&2
  git reset --mixed "$ref" "$@"
}

# ---------------------------------------------------------------------------
# Hard-reset the current branch to a target ref, DISCARDING all local changes.
#   git-hard-reset [ref] [extra git-reset flags...]   (default ref: HEAD)
#
# DESTRUCTIVE: every uncommitted change (staged and unstaged) to tracked files
# is permanently thrown away, and the branch pointer is moved to <ref>. Commits
# left dangling can sometimes be recovered via `git reflog`, but on-disk edits
# that were never committed cannot.
#
# Prompts for confirmation first. Set GIT_RESET_FORCE=1 to skip the prompt
# (e.g. in scripts). Untracked files are left alone — use git-nuke to also
# remove those.
#
# Examples:
#   git-hard-reset                 # discard local changes, stay on HEAD
#   git-hard-reset origin/main     # match the remote exactly
#   GIT_RESET_FORCE=1 git-hard-reset HEAD~2
# ---------------------------------------------------------------------------
git-hard-reset() {
  _git-require-repo "git-hard-reset" || return 1

  local ref="${1:-HEAD}"
  [ -n "${1:-}" ] && shift

  if [ "${GIT_RESET_FORCE:-}" != "1" ]; then
    local branch
    branch="$(_git-current-branch)"
    echo "git-hard-reset: about to DISCARD all uncommitted changes on '${branch:-HEAD}' and reset to '${ref}'." >&2
    printf 'git-hard-reset: continue? [y/N] ' >&2
    local reply
    read -r reply
    case "$reply" in
      [yY] | [yY][eE][sS]) ;;
      *)
        echo "git-hard-reset: aborted" >&2
        return 1
        ;;
    esac
  fi

  echo "git-hard-reset: git reset --hard $ref" >&2
  git reset --hard "$ref" "$@"
}

# ---------------------------------------------------------------------------
# Hard reset AND remove untracked files/directories — a full "back to clean".
#   git-nuke [ref]   (default ref: HEAD)
#
# DESTRUCTIVE: does git-hard-reset (throws away tracked changes) and then
# `git clean -fd` (deletes untracked files and directories, ignored files too
# when GIT_NUKE_IGNORED=1 adds -x). Use when you want the work tree to exactly
# match <ref> with nothing left over.
#
# Honors the same GIT_RESET_FORCE=1 escape hatch as git-hard-reset for the
# confirmation prompt.
# ---------------------------------------------------------------------------
git-nuke() {
  _git-require-repo "git-nuke" || return 1

  local ref="${1:-HEAD}"

  if [ "${GIT_RESET_FORCE:-}" != "1" ]; then
    echo "git-nuke: about to DISCARD all changes AND delete untracked files, resetting to '${ref}'." >&2
    printf 'git-nuke: continue? [y/N] ' >&2
    local reply
    read -r reply
    case "$reply" in
      [yY] | [yY][eE][sS]) ;;
      *)
        echo "git-nuke: aborted" >&2
        return 1
        ;;
    esac
  fi

  GIT_RESET_FORCE=1 git-hard-reset "$ref" || return 1

  local clean_flags="-fd"
  [ "${GIT_NUKE_IGNORED:-}" = "1" ] && clean_flags="-fdx"
  echo "git-nuke: git clean ${clean_flags}" >&2
  git clean "${clean_flags}"
}
