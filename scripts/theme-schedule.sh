#!/usr/bin/env bash
# Day/night color-scheme scheduler (clock-based, not solar).
# Owns org.gnome.desktop.interface color-scheme: prefer-dark between
# DARK_START and DARK_END (may cross midnight), prefer-light otherwise.
# Hours and notify behavior come from theme-schedule.conf (same directory).
# Runs from the theme-schedule.service / theme-schedule.timer systemd
# user units (every 5 minutes + at boot).
#
# Note: Noctalia Theme Mode is "auto" for the shell itself, and its
# "Sync App Color Scheme" toggle is OFF, so this script is the single
# owner of color-scheme. It re-asserts the clock-based value every run.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Defaults, overridden by theme-schedule.conf when present
DARK_START="20:00"
DARK_END="07:00"
NOTIFY=1
CONF="$SCRIPT_DIR/theme-schedule.conf"
[[ -f "$CONF" ]] && source "$CONF"

to_min() {
    local t=$1
    echo $((10#${t%%:*} * 60 + 10#${t##*:}))
}

now_min=$(to_min "$(date +%H:%M)")
start_min=$(to_min "$DARK_START")
end_min=$(to_min "$DARK_END")

in_dark=0
if (( start_min > end_min )); then
    # Window crosses midnight: e.g. 20:00 -> 07:00
    (( now_min >= start_min || now_min < end_min )) && in_dark=1
else
    (( now_min >= start_min && now_min < end_min )) && in_dark=1
fi

target="prefer-light"
mode_name="Light"
(( in_dark )) && target="prefer-dark" && mode_name="Dark"

current=$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null | tr -d "'")
if [[ "$current" != "$target" ]]; then
    gsettings set org.gnome.desktop.interface color-scheme "$target"
    echo "$(date '+%F %T') color-scheme -> $target"
    if (( NOTIFY )); then
        notify-send -r 9995 "Theme Schedule" "$mode_name mode on (until $([[ $in_dark -eq 1 ]] && echo "$DARK_END" || echo "$DARK_START"))"
    fi
fi
