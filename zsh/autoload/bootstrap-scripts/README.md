# zsh-autoload — generic zsh autoloader bootstrap

A zsh-only autoloader that **scans a directory and sources every eligible
script automatically** — no manual registration list. It is a port of the
legacy Bash `setup_aliases.sh`, which carried a hardcoded `script_definitions`
list and `methods/` / `alias/` sourcing; that manual list is intentionally
**replaced by pure directory autoloading**.

On the first shell start it scans the directory, sources each script, and
builds a compiled, concatenated cache (`zcompile` → `.zwc` bytecode). On
subsequent starts it sources that cache instead of re-scanning, rebuilding
automatically when a source file changes or the cache TTL lapses.

## Install

Add one line to your `~/.zshrc`, pointing at this file wherever this repo lives
on your machine (use a path relative to your own checkout — do not copy an
absolute path from elsewhere):

```zsh
source "/path/to/zsh/autoload/bootstrap-scripts/autoload.zsh"
```

Sourced under a non-zsh shell, the loader prints a warning to stderr, defines
nothing, and returns non-zero — it is safe to leave the line in a shared rc.

## Drop-in scripts

Put `*.zsh` or `*.sh` files (defining functions and/or aliases) in the
`examples/` directory next to `autoload.zsh`, or point `ZSH_AUTOLOAD_DIR` at a
directory of your own. They load automatically, in name-sorted order, with no
registration step. See `examples/00-example.zsh` for the expected shape — the
seeded files there are samples; replace them with your own (or set
`ZSH_AUTOLOAD_DIR`).

## Skipping a script

Two ways to exclude a file from loading:

- **Sibling marker** — add an empty file named `<file>.skip` next to it
  (e.g. `tools.zsh` → add `tools.zsh.skip`). The original is left untouched but
  is not sourced.
- **Disable in place** — rename the script so its name ends in `.skip`
  (e.g. `99-disabled.zsh.skip`). The whole file is ignored.

Skipped scripts appear under the `skipped` heading in `autoload-list`.

## Environment knobs

All optional; sensible defaults are used when unset.

| Variable | Purpose | Default |
| --- | --- | --- |
| `ZSH_AUTOLOAD_DIR` | Directory to scan for scripts | `<this dir>/examples` |
| `ZSH_AUTOLOAD_CACHE_DIR` | Where the compiled cache lives | `${XDG_CACHE_HOME:-$HOME/.cache}/zsh-autoload` |
| `ZSH_AUTOLOAD_TTL` | Cache lifetime, in seconds | `86400` (1 day) |
| `ZSH_AUTOLOAD_DEBUG` | Non-empty → per-file status to stderr | _(off)_ |

The loader is **silent by default** and never exports these variables or leaks
options into your interactive shell.

## Cache lifecycle & commands

The cache (`bootstrap.cache.zsh` plus its `.zwc`) rebuilds automatically when
any source file (or the scan directory) is newer than the cache, or when the
cache is older than `ZSH_AUTOLOAD_TTL`. A `zcompile` failure is non-fatal — the
text cache is still sourced.

Public functions (available after the loader runs):

| Command | What it does |
| --- | --- |
| `autoload-list` | Show the scan dir, cache path, and the loaded vs. skipped scripts |
| `autoload-reload` | Re-scan and re-source in the current shell (no new shell needed) |
| `autoload-clear-cache` | Delete the cache (text + `.zwc`); next load rebuilds it |
| `autoload-rebuild-cache` | Clear, re-scan, rebuild the cache, and re-source |

## Layout

```
bootstrap-scripts/
├── autoload.zsh          # entry point: guard, config, boot, public functions
├── lib/
│   ├── _scan.zsh         # directory scan, .skip partitioning, guarded sourcing
│   └── _cache.zsh        # cache build/zcompile + freshness check
├── examples/             # default scan dir (ZSH_AUTOLOAD_DIR) — seeded with samples
│   ├── 00-example.zsh    # sample loadable script (alias + function)
│   └── 99-disabled.zsh.skip   # sample skipped file
└── README.md
```
