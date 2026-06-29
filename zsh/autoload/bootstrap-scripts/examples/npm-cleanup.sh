# npm-cleanup.sh — helper functions for clearing out the JS package-manager
# detritus that accumulates in a project: lockfiles, node_modules, and the
# npm/pnpm download caches.
#
# These wrap the underlying tools so the destructive ones (deleting node_modules,
# removing lockfiles) say exactly what they will throw away and ask before doing
# it, unless you force past the prompt. They are autoloaded — source this file
# (it loads automatically) then call e.g. `npm-clean-modules` or `npm-nuke`.
#
# Functions that operate on a project refuse to run unless the current directory
# looks like a JS project (has a package.json, or a lockfile), so a stray
# invocation in the wrong directory is a no-op rather than a surprise.
#
# Every destructive function honors NPM_CLEAN_FORCE=1 to skip the confirmation
# prompt (e.g. in scripts).

# ---------------------------------------------------------------------------
# Internal: succeed only when the current directory looks like a JS project,
# else warn + return 1. Not meant to be called directly; the project-scoped
# public functions guard with it.
# ---------------------------------------------------------------------------
_npm-require-project() {
  if [ -f package.json ] || [ -f package-lock.json ] || [ -f pnpm-lock.yaml ] || [ -f yarn.lock ]; then
    return 0
  fi
  echo "${1:-npm-helper}: no package.json or lockfile here — not a JS project directory" >&2
  return 1
}

# ---------------------------------------------------------------------------
# Internal: prompt for confirmation, honoring the NPM_CLEAN_FORCE=1 escape
# hatch. Returns 0 to proceed, 1 to abort.
#   _npm-confirm <fn-name> <message>
# ---------------------------------------------------------------------------
_npm-confirm() {
  local fn="$1" msg="$2"
  if [ "${NPM_CLEAN_FORCE:-}" = "1" ]; then
    return 0
  fi
  echo "${fn}: ${msg}" >&2
  printf '%s: continue? [y/N] ' "$fn" >&2
  local reply
  read -r reply
  case "$reply" in
    [yY] | [yY][eE][sS]) return 0 ;;
    *)
      echo "${fn}: aborted" >&2
      return 1
      ;;
  esac
}

# ---------------------------------------------------------------------------
# Delete the project's node_modules directory.
#   npm-clean-modules
#
# DESTRUCTIVE: removes ./node_modules entirely. Harmless in the sense that a
# reinstall (`npm install` / `pnpm install`) rebuilds it, but it can be large
# and slow to recreate. Prompts for confirmation first.
# ---------------------------------------------------------------------------
npm-clean-modules() {
  _npm-require-project "npm-clean-modules" || return 1

  if [ ! -d node_modules ]; then
    echo "npm-clean-modules: no node_modules directory here — nothing to do" >&2
    return 0
  fi

  local size
  size="$(du -sh node_modules 2>/dev/null | cut -f1)"
  _npm-confirm "npm-clean-modules" "about to delete ./node_modules (${size:-unknown size})." || return 1

  echo "npm-clean-modules: rm -rf node_modules" >&2
  rm -rf node_modules
}

# ---------------------------------------------------------------------------
# Delete lockfiles from the current project.
#   npm-clean-lock [npm|pnpm|yarn|all]   (default: all)
#
# DESTRUCTIVE: removes the chosen lockfile(s) — package-lock.json,
# pnpm-lock.yaml, and/or yarn.lock. Removing a lockfile means the next install
# is free to resolve newer versions, so use deliberately. Prompts first.
#
# Examples:
#   npm-clean-lock            # remove every lockfile present
#   npm-clean-lock npm        # only package-lock.json
#   npm-clean-lock pnpm
# ---------------------------------------------------------------------------
npm-clean-lock() {
  _npm-require-project "npm-clean-lock" || return 1

  local which="${1:-all}"
  local -a targets=()
  case "$which" in
    npm) targets=(package-lock.json) ;;
    pnpm) targets=(pnpm-lock.yaml) ;;
    yarn) targets=(yarn.lock) ;;
    all) targets=(package-lock.json pnpm-lock.yaml yarn.lock) ;;
    *)
      echo "npm-clean-lock: unknown target '$which' (use npm|pnpm|yarn|all)" >&2
      return 1
      ;;
  esac

  local -a present=()
  local f
  for f in "${targets[@]}"; do
    [ -f "$f" ] && present+=("$f")
  done

  if [ "${#present[@]}" -eq 0 ]; then
    echo "npm-clean-lock: no matching lockfile here — nothing to do" >&2
    return 0
  fi

  _npm-confirm "npm-clean-lock" "about to delete: ${present[*]}." || return 1

  echo "npm-clean-lock: rm -f ${present[*]}" >&2
  rm -f "${present[@]}"
}

# ---------------------------------------------------------------------------
# Clean the global npm cache.
#   npm-clean-cache
#
# Runs `npm cache clean --force`. This touches the shared npm download cache in
# your home directory, not the current project, so it affects every project.
# A no-op if npm is not installed. Prompts first.
# ---------------------------------------------------------------------------
npm-clean-cache() {
  if ! command -v npm >/dev/null 2>&1; then
    echo "npm-clean-cache: npm not found on PATH — skipping" >&2
    return 0
  fi

  _npm-confirm "npm-clean-cache" "about to run 'npm cache clean --force' (clears the global npm cache)." || return 1

  echo "npm-clean-cache: npm cache clean --force" >&2
  npm cache clean --force
}

# ---------------------------------------------------------------------------
# Clean the global pnpm content-addressable store.
#   npm-clean-pnpm
#
# Runs `pnpm store prune`, which removes packages from the global pnpm store
# that are not referenced by any project. This is the safe pnpm cache cleanup —
# it never deletes packages still in use. A no-op if pnpm is not installed.
# Prompts first.
# ---------------------------------------------------------------------------
npm-clean-pnpm() {
  if ! command -v pnpm >/dev/null 2>&1; then
    echo "npm-clean-pnpm: pnpm not found on PATH — skipping" >&2
    return 0
  fi

  _npm-confirm "npm-clean-pnpm" "about to run 'pnpm store prune' (removes unreferenced packages from the global pnpm store)." || return 1

  echo "npm-clean-pnpm: pnpm store prune" >&2
  pnpm store prune
}

# ---------------------------------------------------------------------------
# Full project reset: remove node_modules AND lockfiles in one go.
#   npm-nuke [npm|pnpm|yarn|all]   (default lockfile target: all)
#
# DESTRUCTIVE: deletes ./node_modules and the chosen lockfile(s) so the next
# install starts completely fresh. Does NOT touch the global caches — use
# npm-clean-cache / npm-clean-pnpm for those.
#
# Honors the same NPM_CLEAN_FORCE=1 escape hatch; asks once up front, then runs
# the underlying steps without re-prompting.
# ---------------------------------------------------------------------------
npm-nuke() {
  _npm-require-project "npm-nuke" || return 1

  local which="${1:-all}"
  _npm-confirm "npm-nuke" "about to DELETE ./node_modules and lockfile(s) [${which}] for a clean reinstall." || return 1

  NPM_CLEAN_FORCE=1 npm-clean-modules
  NPM_CLEAN_FORCE=1 npm-clean-lock "$which"
  echo "npm-nuke: done — run 'npm install' or 'pnpm install' to rebuild" >&2
}
