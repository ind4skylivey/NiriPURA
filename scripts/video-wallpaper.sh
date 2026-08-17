#!/usr/bin/env bash
# video-wallpaper.sh - Set video wallpaper on specific monitor
# Usage: ./video-wallpaper.sh <connector> <video_path>
# Example: ./video-wallpaper.sh DP-1 ~/Pictures/backgrounds/Live-Wallpapers/abi-toads-cozy-winter.1920x1080.mp4
#          ./video-wallpaper.sh stop DP-1  (to stop)

set -e

CONNECTOR="${1:-}"
VIDEO="${2:-}"
VIDEO_DIRS=(
    "/media/il1v3y/HD2/HDfiles/shenanigans/Repos/Personal/sddm-themes/Backgrounds"
)

get_videos() {
    local conn="${1:-}"
    for dir in "${VIDEO_DIRS[@]}"; do
        if [[ -d "$dir" ]]; then
            ls "$dir"/*.mp4 "$dir"/*.webm "$dir"/*.mkv 2>/dev/null | sort
        fi
    done
}

# Function to kill existing mpvpaper for connector
kill_mpvpaper() {
    local conn="$1"
    pkill -f "mpvpaper .* $conn " 2>/dev/null || true
    echo "Stopped video wallpaper on $conn"
}

# Function to start video wallpaper
start_video() {
    local conn="$1"
    local vid="$2"

    if [[ ! -f "$vid" ]]; then
        echo "Error: Video not found: $vid"
        echo "Available videos:"
        ls "$VIDEO_DIR/"
        exit 1
    fi

    # Kill existing instance first
    kill_mpvpaper "$conn"

    # Start mpvpaper
    mpvpaper -f -o "loop-file=inf panscan=1.0 no-audio hwdec=auto" "$conn" "$vid"
    echo "Video wallpaper started on $conn"
}

# Check if mpvpaper is running for connector
is_running() {
    local conn="$1"
    pgrep -f "mpvpaper .* $conn " >/dev/null 2>&1
}

# Function to get current video for connector
get_current_video() {
    local conn="$1"
    pgrep -f "mpvpaper .* $conn " 2>/dev/null | xargs -I{} cat /proc/{}/cmdline 2>/dev/null | tr '\0' ' ' | grep -o "[^ ]*\.mp4\|[^ ]*\.webm\|[^ ]*\.mkv" | tail -1 || true
}

# Toggle video wallpaper
toggle_video() {
    local conn="${1:-DP-1}"

    if is_running "$conn"; then
        kill_mpvpaper "$conn"
    else
        # Start with first video in directories
        local vid="${2:-}"
        if [[ -z "$vid" ]]; then
            vid=$(get_videos | head -1)
        fi
        if [[ -n "$vid" && -f "$vid" ]]; then
            start_video "$conn" "$vid"
        else
            echo "No video found"
            exit 1
        fi
    fi
}

# Cycle to next video
cycle_video() {
    local conn="${1:-DP-1}"

    local videos=()
    while IFS= read -r vid; do
        videos+=("$vid")
    done < <(get_videos)

    if [[ ${#videos[@]} -eq 0 ]]; then
        echo "No videos found"
        exit 1
    fi

    local current=""
    if is_running "$conn"; then
        current=$(get_current_video "$conn")
        kill_mpvpaper "$conn"
    fi

    # Find next video after current
    local next_vid=""
    local found=0
    for vid in "${videos[@]}"; do
        if [[ $found -eq 1 ]]; then
            next_vid="$vid"
            break
        fi
        if [[ "$vid" == "$current" ]]; then
            found=1
        fi
    done

    # If no next found (was last), use first
    if [[ -z "$next_vid" ]]; then
        next_vid="${videos[0]}"
    fi

    start_video "$conn" "$next_vid"
    echo "Switched to: $(basename "$next_vid")"
}

# Main
case "$CONNECTOR" in
    toggle)
        toggle_video "${2:-DP-1}" "${3:-}"
        ;;
    next)
        cycle_video "${2:-DP-1}"
        ;;
    stop)
        kill_mpvpaper "${VIDEO:-DP-1}"
        ;;
    list)
        echo "Available videos:"
        get_videos | xargs -I{} basename {}
        ;;
    "")
        echo "Usage: video-wallpaper.sh <connector> <video_path>"
        echo "       video-wallpaper.sh toggle <connector>"
        echo "       video-wallpaper.sh next <connector>"
        echo "       video-wallpaper.sh stop <connector>"
        echo "       video-wallpaper.sh list"
        echo ""
        echo "Available monitors: DP-1 (primary), DP-2, HDMI-A-1"
        echo "Video directories:"
        for dir in "${VIDEO_DIRS[@]}"; do
            echo "  - $dir"
        done
        ;;
    *)
        if [[ -z "$VIDEO" ]]; then
            echo "Error: Video path required"
            exit 1
        fi
        start_video "$CONNECTOR" "$VIDEO"
        ;;
esac
