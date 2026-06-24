# Sample autoloaded script — defines one alias and one function.
# Drop your own *.zsh / *.sh files alongside this one; they load automatically.
# Delete or rename this file to <name>.skip to disable it.

alias ll='ls -lah'

mkcd() {
  mkdir -p "$1" && cd "$1"
}
