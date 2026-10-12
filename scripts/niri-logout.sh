#!/usr/bin/env bash
# ~/.config/niri/scripts/niri-logout.sh
# Power menu using rofi/wofi -> lock/suspend/reboot/shutdown/logout

CHOICE=$(printf "Lock\nSuspend\nReboot\nShutdown\nLogout" | rofi -dmenu -p "Power")
# Alternative wayland-native: wofi -dmenu -p "Power"

case "$CHOICE" in
    "Lock")     swaylock ;;
    "Suspend")  systemctl suspend ;;
    "Reboot")   systemctl reboot ;;
    "Shutdown") systemctl poweroff ;;
    "Logout")   niri msg action quit ;;
esac
