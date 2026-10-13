#!/usr/bin/env bash
# ~/.config/niri/scripts/night-light.sh
# Toggles gammastep night light (wlr-gamma-control via niri).
# Buenos Aires: 6500K day / 3500K night, automatic sunset transition.
# Usage: night-light.sh [start|stop|status]

LAT="-34.6"
LON="-58.38"
PID_FILE="${XDG_RUNTIME_DIR:-/tmp/night-light-$UID}/night-light.pid"
mkdir -p "$(dirname "$PID_FILE")" 2>/dev/null || true

# PID of the gammastep instance started by this session, if it is still alive
our_pid() {
    [[ -f "$PID_FILE" ]] || return 1
    local pid
    pid=$(cat "$PID_FILE" 2>/dev/null) || return 1
    [[ "$pid" =~ ^[0-9]+$ ]] || return 1
    kill -0 "$pid" 2>/dev/null || { rm -f "$PID_FILE"; return 1; }
    echo "$pid"
}

start() {
    # No double-start: keep a single instance of our own
    if our_pid >/dev/null; then
        notify-send -r 9995 "Night Light" "Already on"
        return 0
    fi
    if ! command -v gammastep >/dev/null; then
        notify-send -r 9995 "Night Light" "gammastep not found"
        return 1
    fi
    gammastep -l "$LAT:$LON" -t 6500:3500 &
    echo $! > "$PID_FILE"
    # Give it a moment; report failure if it exited during startup
    sleep 0.5
    if kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        notify-send -r 9995 "Night Light" "On (auto BA: 6500K day / 3500K night)"
    else
        rm -f "$PID_FILE"
        notify-send -r 9995 "Night Light" "gammastep failed to start"
        return 1
    fi
}

stop() {
    local pid
    if pid=$(our_pid); then
        kill "$pid" 2>/dev/null
        rm -f "$PID_FILE"
        notify-send -r 9995 "Night Light" "Off"
    fi
}

case "${1:-toggle}" in
    start) start ;;
    stop)  stop ;;
    status)
        our_pid >/dev/null && echo "on" || echo "off"
        ;;
    toggle)
        if our_pid >/dev/null; then
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
