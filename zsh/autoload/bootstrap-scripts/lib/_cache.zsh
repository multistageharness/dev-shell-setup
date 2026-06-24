# zsh-autoload :: lib/_cache.zsh
# Compiled-cache generation and freshness checking.
# Sourced by autoload.zsh; assumes _zautoload_dbg is defined and (for the
# freshness check) that zsh/stat and zsh/datetime have been zmodload'ed.

# _zautoload_build_cache <cache_file> <eligible_file>...
# Concatenate the eligible scripts into a single cache file, written
# atomically (write to a temp file, then mv into place). The cache header
# republishes the eligible list so a later cache-only boot can populate
# autoload-list without re-scanning. After the atomic mv, the text cache is
# zcompiled to <cache_file>.zwc; a zcompile failure is non-fatal (the text
# cache remains sourceable, and `source <cache_file>` auto-prefers the .zwc
# when present and newer).
_zautoload_build_cache() {
  emulate -L zsh
  setopt local_options
  local cache_file="$1"; shift
  local -a files=("$@")
  local tmp="${cache_file}.tmp.$$"
  mkdir -p "${cache_file:h}" || return 1
  {
    print -- "# zsh-autoload compiled cache — generated; do not edit"
    # Republish the loaded set so cache-only boots can answer autoload-list.
    print -r -- "typeset -g -a _ZAUTOLOAD_ELIGIBLE=( ${(q)files[@]} )"
    local f
    for f in "${files[@]}"; do
      print -- "# >>> $f"
      cat -- "$f"
      print -- ""
    done
  } >| "$tmp" || { rm -f -- "$tmp"; return 1; }
  mv -f -- "$tmp" "$cache_file" || { rm -f -- "$tmp"; return 1; }
  # zcompile writes ${cache_file}.zwc; source "$cache_file" auto-prefers it.
  if ! zcompile -- "$cache_file" 2>/dev/null; then
    _zautoload_dbg "zcompile failed for $cache_file (will source text cache)"
  fi
  return 0
}

# _zautoload_cache_is_fresh <cache_file> <scan_dir> <ttl_seconds>
# Return 0 (fresh) iff the cache exists, no source file (or the scan dir
# itself) is newer than the cache, and the cache is within its TTL window.
# Any other condition returns non-zero (stale → caller re-scans).
_zautoload_cache_is_fresh() {
  emulate -L zsh
  setopt local_options extended_glob no_nomatch
  local cache_file="$1" scan_dir="$2" ttl="$3"
  [[ -f "$cache_file" ]] || return 1

  local cache_mtime
  cache_mtime=$(zstat +mtime -- "$cache_file" 2>/dev/null) || return 1

  # Scan-dir mtime changes when files are added or removed.
  local dir_mtime
  dir_mtime=$(zstat +mtime -- "$scan_dir" 2>/dev/null)
  [[ -n "$dir_mtime" ]] && (( dir_mtime > cache_mtime )) && return 1

  # Any source file newer than the cache → stale.
  local f fmtime
  for f in "$scan_dir"/*.zsh(N.) "$scan_dir"/*.sh(N.) "$scan_dir"/*.skip(N.); do
    fmtime=$(zstat +mtime -- "$f" 2>/dev/null) || continue
    (( fmtime > cache_mtime )) && return 1
  done

  # TTL cap.
  (( EPOCHSECONDS - cache_mtime > ttl )) && return 1
  return 0
}
