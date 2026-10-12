#!/usr/bin/env bash
# ~/.config/niri/scripts/toggle-output-profile.sh
# Toggles between "work" and "gaming" Hz profiles for LG UltraGear (DP-1).
# ASUS (DP-2) and Samsung (HDMI-A-1) remain unchanged.

STATE_FILE="$HOME/.cache/niri-output-profile"
PROFILE=$(cat "$STATE_FILE" 2>/dev/null || echo "work")

if [ "$PROFILE" = "work" ]; then
    niri msg action do-screen-transition
    niri msg output "DP-1" mode "1920x1080@179.961"
    echo "gaming" > "$STATE_FILE"
    notify-send -r 9994 "Niri" "Profile: gaming (180Hz)"
else
    niri msg action do-screen-transition
    niri msg output "DP-1" mode "1920x1080@143.981"
    echo "work" > "$STATE_FILE"
    notify-send -r 9994 "Niri" "Profile: work (144Hz)"
fi
