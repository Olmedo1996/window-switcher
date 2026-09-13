#!/bin/bash
# Best-effort enrichment for the Window Switcher: for every open window, walk
# to the shell running inside it and report its current directory plus the
# foreground command.
#
# Output, one line per window (tab-separated):
#   <address-without-0x>\t<cwd>\t<command>
#
# Errors are silent: a window with no readable /proc simply emits empty fields
# and the plugin falls back to the window title.

hyprctl -j clients 2>/dev/null \
  | jq -r '.[] | select(.pid > 0) | [.address, (.pid | tostring)] | @tsv' \
  | while IFS=$'\t' read -r addr pid; do
      [ -n "$addr" ] || continue

      target="$pid"
      child=$(pgrep -P "$pid" 2>/dev/null | head -n1)
      [ -n "$child" ] && target="$child"

      cwd=$(readlink -f "/proc/$target/cwd" 2>/dev/null)

      # Field 8 of /proc/<pid>/stat is the tty process-group id; when a
      # foreground program owns the terminal, that pid is the command.
      tpgid=$(awk '{print $8}' "/proc/$target/stat" 2>/dev/null)
      cmd=""
      if [ -n "$tpgid" ] && [ -d "/proc/$tpgid" ]; then
        cmd=$(cat "/proc/$tpgid/comm" 2>/dev/null)
      fi
      [ -z "$cmd" ] && cmd=$(cat "/proc/$target/comm" 2>/dev/null)

      addr="${addr#0x}"
      printf '%s\t%s\t%s\n' "$addr" "$cwd" "$cmd"
    done
