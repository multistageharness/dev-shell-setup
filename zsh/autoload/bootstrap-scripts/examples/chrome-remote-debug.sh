# chrome-remote-debug.sh — helper functions for launching Google Chrome with the
# Chrome DevTools Protocol (CDP) enabled for remote debugging.
#
# Two transports are supported (see the CDP docs):
#   1. TCP port      — `--remote-debugging-port=<port>` exposes an HTTP/WebSocket
#                      endpoint (e.g. http://localhost:9222). Use port 0 to let
#                      the OS pick a free port (Chrome prints it to stderr).
#   2. Stdio pipes   — `--remote-debugging-pipe` reads CDP from FD 3, writes to
#                      FD 4. Useful in sandboxes where binding a TCP port is
#                      restricted, and avoids the open-port race entirely.
#
# Companion flags this script always pairs with the debug flag:
#   --user-data-dir   forces an isolated instance so the debug server actually
#                     starts (otherwise Chrome just opens a tab in your running
#                     session and ignores the flag).
#   --headless        optional; runs Chrome without a visible window.
#
# Source this file (it is autoloaded) then call e.g. `chrome-debug 9222`.

# ---------------------------------------------------------------------------
# Locate the Chrome / Chromium binary for the current platform and echo its
# absolute path. This is the single source of truth every other function uses
# to find Chrome.
#
#   chrome-find-path
#
# Resolution order:
#   1. $CHROME_BIN — explicit override, if set and executable.
#   2. A list of well-known macOS .app paths and PATH command names.
#
# Echoes the path on success; returns non-zero (and warns) if none is found.
# Tip: to skip the filesystem scan, resolve once and export it for the session:
#   export CHROME_BIN="$(chrome-find-path)"
# ---------------------------------------------------------------------------
chrome-find-path() {
  # 1. Explicit override always wins.
  if [ -n "${CHROME_BIN:-}" ] && [ -x "${CHROME_BIN}" ]; then
    printf '%s\n' "${CHROME_BIN}"
    return 0
  fi

  # 2. Search known locations and the PATH.
  local candidates=(
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
    "/Applications/Google Chrome Canary.app/Contents/MacOS/Google Chrome Canary"
    "/Applications/Chromium.app/Contents/MacOS/Chromium"
    "google-chrome"
    "google-chrome-stable"
    "chromium"
    "chromium-browser"
    "chrome"
  )

  local c
  for c in "${candidates[@]}"; do
    if [ -x "$c" ]; then
      printf '%s\n' "$c"
      return 0
    fi
    # Fall back to PATH lookup for bare command names.
    if command -v "$c" >/dev/null 2>&1; then
      command -v "$c"
      return 0
    fi
  done

  echo "chrome-find-path: could not find a Chrome/Chromium binary (set \$CHROME_BIN)" >&2
  return 1
}

# Back-compat alias — earlier callers used this name.
chrome-debug-bin() {
  chrome-find-path "$@"
}

# ---------------------------------------------------------------------------
# Launch Chrome with the TCP debugging port enabled.
#   chrome-debug [port] [extra chrome flags...]
#
#   port    TCP port for the CDP endpoint. Default 9222. Use 0 to have the OS
#           assign a free port (Chrome prints the chosen port to stderr).
#
# Environment overrides:
#   CHROME_BIN            path to the Chrome binary
#   CHROME_DEBUG_PROFILE  user-data-dir to use (default: a per-port temp dir)
#   CHROME_DEBUG_HEADLESS set to 1 to add --headless=new
#
# Examples:
#   chrome-debug                       # port 9222, windowed
#   chrome-debug 9333                  # custom port
#   chrome-debug 0                     # OS-assigned port
#   CHROME_DEBUG_HEADLESS=1 chrome-debug 9222 --disable-gpu
# ---------------------------------------------------------------------------
chrome-debug() {
  local port="${1:-9222}"
  shift 2>/dev/null || true

  local bin
  bin="$(chrome-find-path)" || return 1

  local profile="${CHROME_DEBUG_PROFILE:-${TMPDIR:-/tmp}/chrome-debug-${port}}"
  mkdir -p "$profile"

  local flags=(
    "--remote-debugging-port=${port}"
    "--user-data-dir=${profile}"
    "--no-first-run"
    "--no-default-browser-check"
  )
  [ "${CHROME_DEBUG_HEADLESS:-}" = "1" ] && flags+=("--headless=new")

  echo "chrome-debug: launching $bin" >&2
  echo "chrome-debug:   port    = ${port}$([ "$port" = "0" ] && echo ' (OS-assigned; see stderr below)')" >&2
  echo "chrome-debug:   profile = ${profile}" >&2
  [ "$port" != "0" ] && echo "chrome-debug:   inspect → http://localhost:${port}/json/version" >&2

  "$bin" "${flags[@]}" "$@"
}

# ---------------------------------------------------------------------------
# Launch Chrome in the background (detached) with the TCP debugging port, then
# wait until the CDP endpoint answers before returning.
#   chrome-debug-bg [port] [extra chrome flags...]
#
# Prints the PID. The endpoint URL is http://localhost:<port>. Stop it with
# `chrome-debug-stop <port>` or by killing the PID.
# ---------------------------------------------------------------------------
chrome-debug-bg() {
  local port="${1:-9222}"

  if [ "$port" = "0" ]; then
    echo "chrome-debug-bg: cannot wait on an OS-assigned port (use a fixed port)" >&2
    return 2
  fi

  ( CHROME_DEBUG_HEADLESS="${CHROME_DEBUG_HEADLESS:-1}" chrome-debug "$@" \
      >"${TMPDIR:-/tmp}/chrome-debug-${port}.log" 2>&1 & echo $! ) | {
    read -r pid
    echo "chrome-debug-bg: started pid ${pid}, waiting for http://localhost:${port} ..." >&2

    local i
    for i in $(seq 1 50); do
      if chrome-debug-check "$port" >/dev/null 2>&1; then
        echo "chrome-debug-bg: ready on http://localhost:${port} (pid ${pid})" >&2
        printf '%s\n' "$pid"
        return 0
      fi
      sleep 0.2
    done

    echo "chrome-debug-bg: timed out waiting for port ${port}; see ${TMPDIR:-/tmp}/chrome-debug-${port}.log" >&2
    return 1
  }
}

# ---------------------------------------------------------------------------
# Launch Chrome using stdio pipes instead of a TCP port.
#   chrome-debug-pipe [extra chrome flags...]
#
# Chrome reads CDP commands from FD 3 and writes responses to FD 4, messages
# separated by a NUL (\0). This is the sandbox-friendly transport — no TCP bind,
# no open-port race. Your controlling tool is responsible for wiring FDs 3/4.
# ---------------------------------------------------------------------------
chrome-debug-pipe() {
  local bin
  bin="$(chrome-find-path)" || return 1

  local profile="${CHROME_DEBUG_PROFILE:-${TMPDIR:-/tmp}/chrome-debug-pipe}"
  mkdir -p "$profile"

  local flags=(
    "--remote-debugging-pipe"
    "--user-data-dir=${profile}"
    "--no-first-run"
    "--no-default-browser-check"
  )
  [ "${CHROME_DEBUG_HEADLESS:-}" = "1" ] && flags+=("--headless=new")

  echo "chrome-debug-pipe: launching $bin (CDP on FD 3/FD 4, NUL-delimited)" >&2
  echo "chrome-debug-pipe:   profile = ${profile}" >&2

  "$bin" "${flags[@]}" "$@"
}

# ---------------------------------------------------------------------------
# Probe a running CDP endpoint and print its /json/version payload.
#   chrome-debug-check [port]   (default 9222)
# Returns non-zero if the endpoint is not reachable.
# ---------------------------------------------------------------------------
chrome-debug-check() {
  local port="${1:-9222}"
  if ! command -v curl >/dev/null 2>&1; then
    echo "chrome-debug-check: curl not found" >&2
    return 2
  fi
  curl -fsS "http://localhost:${port}/json/version"
}

# ---------------------------------------------------------------------------
# List the inspectable targets (tabs) on a running endpoint.
#   chrome-debug-targets [port]   (default 9222)
# ---------------------------------------------------------------------------
chrome-debug-targets() {
  local port="${1:-9222}"
  if ! command -v curl >/dev/null 2>&1; then
    echo "chrome-debug-targets: curl not found" >&2
    return 2
  fi
  if command -v jq >/dev/null 2>&1; then
    curl -fsS "http://localhost:${port}/json/list" | jq -r '.[] | "\(.type)\t\(.title)\t\(.url)\n  ws: \(.webSocketDebuggerUrl)"'
  else
    curl -fsS "http://localhost:${port}/json/list"
  fi
}

# ---------------------------------------------------------------------------
# Stop a Chrome debug instance launched on the given port by matching its
# --remote-debugging-port flag.
#   chrome-debug-stop [port]   (default 9222)
# ---------------------------------------------------------------------------
chrome-debug-stop() {
  local port="${1:-9222}"
  local pids
  pids="$(pgrep -f -- "--remote-debugging-port=${port}" 2>/dev/null)"
  if [ -z "$pids" ]; then
    echo "chrome-debug-stop: no Chrome instance found on port ${port}" >&2
    return 1
  fi
  echo "chrome-debug-stop: killing pids: ${pids}" >&2
  # shellcheck disable=SC2086
  kill $pids 2>/dev/null
}
