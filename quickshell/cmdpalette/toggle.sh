#!/usr/bin/env bash
# Toggle the S1B.CMD command palette (Quickshell config "cmdpalette").
# -x makes pgrep/pkill match the WHOLE command line, so only this process
# is touched (never a shell whose arguments merely mention it).
PAT='(/usr/bin/)?(qs|quickshell) (-c|--config) cmdpalette'
if pgrep -x -f "$PAT" >/dev/null; then
    pkill -x -f "$PAT"
    exit 0
fi
CP_OUTPUT="$(niri msg -j focused-output 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["name"])' 2>/dev/null)"
export CP_OUTPUT="${CP_OUTPUT:-DP-1}"
setsid -f qs -c cmdpalette >/tmp/cmd-palette.log 2>&1
