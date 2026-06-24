# zsh-autoload :: lib/_scan.zsh
# Directory enumeration, .skip partitioning, and guarded sourcing.
# Sourced by autoload.zsh; all functions assume _zautoload_dbg is defined.
#
# Note on out-params: functions that return arrays by name use internal locals
# prefixed "_za_" so they never collide with a caller-supplied result-array
# name (e.g. a caller passing "eligible" would otherwise be shadowed by a
# local of the same name and the assignment would be lost).

# _zautoload_scan <dir> <result_array_name>
# Enumerate candidate scripts (*.zsh, *.sh) plus disable-markers (*.skip),
# regular files only, name-sorted within each pattern. A missing or empty
# directory yields an empty array and status 0 (nullglob, no glob error).
_zautoload_scan() {
  emulate -L zsh
  setopt local_options extended_glob no_nomatch
  local _za_dir="$1" _za_resultvar="$2"
  local -a _za_found
  # N = nullglob, . = regular files only, n = numeric/name sort
  _za_found=( "$_za_dir"/*.zsh(N.n) "$_za_dir"/*.sh(N.n) "$_za_dir"/*.skip(N.n) )
  set -A "$_za_resultvar" "${_za_found[@]}"
}

# _zautoload_scan_split <dir> <eligible_array_name> <skipped_array_name>
# Partition the scanned candidates into eligible (to source) and skipped.
#
# .skip convention:
#   - a sibling marker "<file>.skip" disables "<file>" (the script is skipped,
#     the marker itself is not listed);
#   - a file whose own name ends in ".skip" with no live sibling (e.g.
#     "99-disabled.zsh.skip") is a disabled-in-place script and is listed as
#     skipped.
_zautoload_scan_split() {
  emulate -L zsh
  setopt local_options extended_glob no_nomatch
  local _za_dir="$1" _za_elig_var="$2" _za_skip_var="$3"
  local -a _za_candidates _za_eligible _za_skipped
  _zautoload_scan "$_za_dir" _za_candidates
  local _za_f _za_base
  for _za_f in "${_za_candidates[@]}"; do
    if [[ "$_za_f" == *.skip ]]; then
      _za_base="${_za_f%.skip}"
      [[ -e "$_za_base" ]] && continue       # marker for a live script; not itself a script
      _za_skipped+=("$_za_f")                # disabled-in-place script
    elif [[ -e "${_za_f}.skip" ]]; then
      _za_skipped+=("$_za_f")                # has a sibling disable marker
    else
      _za_eligible+=("$_za_f")
    fi
  done
  set -A "$_za_elig_var" "${_za_eligible[@]}"
  set -A "$_za_skip_var" "${_za_skipped[@]}"
}

# _zautoload_source <file>...
# Source each file, guarding every one so a single failure (unreadable file,
# non-zero return, or syntax error) never aborts shell startup. Returns 1 if
# any file failed, 0 otherwise. All status is routed through _zautoload_dbg.
_zautoload_source() {
  emulate -L zsh
  setopt local_options
  local _za_f _za_rc=0
  for _za_f in "$@"; do
    [[ -r "$_za_f" ]] || { _zautoload_dbg "unreadable: $_za_f"; _za_rc=1; continue; }
    if ! source "$_za_f"; then
      _zautoload_dbg "[fail] $_za_f"; _za_rc=1
    else
      _zautoload_dbg "[ok]   $_za_f"
    fi
  done
  return $_za_rc
}
