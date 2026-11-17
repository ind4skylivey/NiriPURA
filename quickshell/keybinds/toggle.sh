#!/usr/bin/env bash
# Toggle the niri keybinds cheatsheet (Quickshell config "keybinds").
# -x makes pgrep/pkill match the WHOLE command line, so only the cheatsheet
# process is touched (never a shell whose arguments merely mention it).
PAT='(/usr/bin/)?(qs|quickshell) (-c|--config) keybinds'
if pgrep -x -f "$PAT" >/dev/null; then
    pkill -x -f "$PAT"
    exit 0
fi
KB_OUTPUT="$(niri msg -j focused-output 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["name"])' 2>/dev/null)"
export KB_OUTPUT="${KB_OUTPUT:-DP-1}"
setsid -f qs -c keybinds >/tmp/keybinds-cheatsheet.log 2>&1
