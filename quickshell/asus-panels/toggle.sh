#!/usr/bin/env bash
# Toggle the ASUS vertical Quickshell panels (config "asus-panels").
# -x makes pgrep/pkill match the WHOLE command line.
PAT='(/usr/bin/)?(qs|quickshell) (-c|--config) asus-panels'
mode="${1:-toggle}"
if pgrep -x -f "$PAT" >/dev/null; then
    if [ "$mode" = "start" ]; then
        exit 0
    fi
    pkill -x -f "$PAT"
    [ "$mode" = "stop" ] && exit 0
    [ "$mode" = "toggle" ] && exit 0
fi
[ "$mode" = "stop" ] && exit 0
setsid -f qs -c asus-panels >/tmp/asus-panels.log 2>&1
