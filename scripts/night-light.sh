#!/usr/bin/env bash
# ~/.config/niri/scripts/night-light.sh
# Toggles gammastep night light (wlr-gamma-control via niri).
# Buenos Aires: 6500K day / 3500K night, automatic sunset transition.
# Usage: night-light.sh [start|stop|status]

LAT="-34.6"
LON="-58.38"

start() {
    # No double-start: keep a single instance
    if pgrep -x gammastep >/dev/null; then
        notify-send -r 9995 "Night Light" "Already on"
        return 0
    fi
    gammastep -l "$LAT:$LON" -t 6500:3500 &
    notify-send -r 9995 "Night Light" "On (auto BA: 6500K day / 3500K night)"
}

stop() {
    pkill -x gammastep && notify-send -r 9995 "Night Light" "Off" || true
}

case "${1:-toggle}" in
    start) start ;;
    stop)  stop ;;
    status)
        pgrep -x gammastep >/dev/null && echo "on" || echo "off"
        ;;
    toggle)
        if pgrep -x gammastep >/dev/null; then
            stop
        else
            start
        fi
        ;;
    *)
        echo "Usage: $0 [start|stop|status]" >&2
        exit 1
        ;;
esac
