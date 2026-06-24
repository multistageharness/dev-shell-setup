#!/usr/bin/env zsh
# =============================================================================
# zsh-autoload — generic, memory-safe zsh autoloader bootstrap
# =============================================================================
# Scans a directory and sources every eligible script (*.zsh / *.sh defining
# functions or aliases) automatically — no manual registration list. Files
# marked with the .skip convention are ignored. A compiled, concatenated cache
# (zcompile → .zwc bytecode) is sourced instead of re-scanning on subsequent
# shell starts, and is rebuilt automatically when sources change or the TTL
# lapses.
#
# This replaces the legacy Bash `setup_aliases.sh` hardcoded `script_definitions`
# list with pure directory autoloading. It is zsh-only by design.
#
# Install — add to ~/.zshrc (use a path relative to where this repo lives):
#   source "/path/to/zsh/autoload/bootstrap-scripts/autoload.zsh"
#
# Environment knobs (all optional):
#   ZSH_AUTOLOAD_DIR        scan directory          (default: <here>/examples)
#   ZSH_AUTOLOAD_CACHE_DIR  cache directory         (default: $XDG_CACHE_HOME/zsh-autoload)
#   ZSH_AUTOLOAD_TTL        cache TTL in seconds     (default: 86400)
#   ZSH_AUTOLOAD_DEBUG      non-empty → verbose to stderr (default: off)
#
# Public functions: autoload-list, autoload-reload, autoload-clear-cache,
#                    autoload-rebuild-cache
# =============================================================================

# --- zsh-only guard ----------------------------------------------------------
if [ -z "${ZSH_VERSION:-}" ]; then
  echo "zsh-autoload: requires zsh; not loaded under this shell" >&2
  return 1 2>/dev/null || exit 1
fi

# --- debug helper ------------------------------------------------------------
# Defined at file scope (before the libs are sourced) and reads the published
# global so it is visible to both the boot flow and the public functions.
_zautoload_dbg() { [[ -n "${_ZAUTOLOAD_DEBUG:-}" ]] && print -u2 "zsh-autoload: $*"; return 0 }

# --- resolve our own directory & load libs -----------------------------------
# ${(%):-%x} expands to the path of the file currently being sourced, which is
# correct even when this file is sourced from inside a function context (unlike
# $0). :A = absolute, :h = dirname.
typeset -g _ZAUTOLOAD_SELF_DIR="${${(%):-%x}:A:h}"
source "$_ZAUTOLOAD_SELF_DIR/lib/_scan.zsh"
source "$_ZAUTOLOAD_SELF_DIR/lib/_cache.zsh"

# =============================================================================
# Public management functions — defined at file scope so they persist in the
# interactive session after _zautoload_boot returns. They read the boot-time
# state published in the _ZAUTOLOAD_* globals.
# =============================================================================

# Discard the compiled cache (text + .zwc) so the next load rebuilds it.
autoload-clear-cache() {
  emulate -L zsh
  setopt local_options
  local cf="${_ZAUTOLOAD_CACHE_FILE:?zsh-autoload not initialized}"
  rm -f -- "$cf" "${cf}.zwc"
  print "zsh-autoload: cache cleared"
}

# Re-scan and re-source in the current shell (no cache dependency), refreshing
# any changed function/alias definitions and the loaded/skipped state.
autoload-reload() {
  emulate -L zsh
  setopt local_options
  local -a eligible skipped
  _zautoload_scan_split "$_ZAUTOLOAD_SCAN_DIR" eligible skipped
  typeset -g -a _ZAUTOLOAD_ELIGIBLE=( "${eligible[@]}" )
  typeset -g -a _ZAUTOLOAD_SKIPPED=( "${skipped[@]}" )
  _zautoload_source "${eligible[@]}"
  print "zsh-autoload: reloaded ${#eligible} script(s)"
}

# Clear → scan → rebuild cache → source.
autoload-rebuild-cache() {
  emulate -L zsh
  setopt local_options
  autoload-clear-cache >/dev/null
  local -a eligible skipped
  _zautoload_scan_split "$_ZAUTOLOAD_SCAN_DIR" eligible skipped
  typeset -g -a _ZAUTOLOAD_ELIGIBLE=( "${eligible[@]}" )
  typeset -g -a _ZAUTOLOAD_SKIPPED=( "${skipped[@]}" )
  _zautoload_build_cache "$_ZAUTOLOAD_CACHE_FILE" "${eligible[@]}"
  _zautoload_source "${eligible[@]}"
  print "zsh-autoload: cache rebuilt (${#eligible} script(s))"
}

# Show the active directories and the loaded vs. skipped script sets.
autoload-list() {
  emulate -L zsh
  setopt local_options
  print "scan dir : ${_ZAUTOLOAD_SCAN_DIR:-<uninitialized>}"
  print "cache    : ${_ZAUTOLOAD_CACHE_FILE:-<uninitialized>}"
  print "loaded (${#_ZAUTOLOAD_ELIGIBLE}):"
  local f
  for f in "${_ZAUTOLOAD_ELIGIBLE[@]}"; do print "  + ${f:t}"; done
  print "skipped (${#_ZAUTOLOAD_SKIPPED}):"
  for f in "${_ZAUTOLOAD_SKIPPED[@]}"; do print "  - ${f:t}"; done
}

# =============================================================================
# Internal boot helpers
# =============================================================================

# Scan, publish state, build the cache, and source the eligible scripts.
_zautoload_rescan_and_source() {
  emulate -L zsh
  setopt local_options extended_glob no_nomatch
  local scan_dir="$1" cache_file="$2"
  local -a eligible skipped
  _zautoload_scan_split "$scan_dir" eligible skipped
  typeset -g -a _ZAUTOLOAD_ELIGIBLE=( "${eligible[@]}" )
  typeset -g -a _ZAUTOLOAD_SKIPPED=( "${skipped[@]}" )
  _zautoload_build_cache "$cache_file" "${eligible[@]}"
  _zautoload_source "${eligible[@]}"
}

# --- boot orchestrator -------------------------------------------------------
_zautoload_boot() {
  emulate -L zsh
  setopt local_options extended_glob no_nomatch warn_create_global

  # Own directory (local; must not leak into the interactive shell).
  local SELF_DIR="${${(%):-%x}:A:h}"

  # Config: env-or-default. Kept local; nothing is exported.
  local scan_dir="${ZSH_AUTOLOAD_DIR:-$SELF_DIR/examples}"
  local cache_dir="${ZSH_AUTOLOAD_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/zsh-autoload}"
  local ttl="${ZSH_AUTOLOAD_TTL:-86400}"
  local debug="${ZSH_AUTOLOAD_DEBUG:-}"
  local cache_file="$cache_dir/bootstrap.cache.zsh"

  # Publish the state the public functions and debug helper read.
  typeset -g _ZAUTOLOAD_DEBUG=$debug
  typeset -g _ZAUTOLOAD_SCAN_DIR=$scan_dir
  typeset -g _ZAUTOLOAD_CACHE_FILE=$cache_file

  _zautoload_dbg "scan_dir=$scan_dir"
  _zautoload_dbg "cache_dir=$cache_dir"

  zmodload zsh/stat zsh/datetime 2>/dev/null

  if _zautoload_cache_is_fresh "$cache_file" "$scan_dir" "$ttl"; then
    _zautoload_dbg "load: cache ($cache_file)"
    if ! source "$cache_file"; then
      _zautoload_dbg "cache source failed — rescanning"
      _zautoload_rescan_and_source "$scan_dir" "$cache_file"
    fi
  else
    _zautoload_dbg "load: scan ($scan_dir)"
    _zautoload_rescan_and_source "$scan_dir" "$cache_file"
  fi

  # Individual script failures are non-fatal and already logged via debug;
  # never propagate a non-zero status to the sourcing ~/.zshrc.
  return 0
}

_zautoload_boot "$@"
