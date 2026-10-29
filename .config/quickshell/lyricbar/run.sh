#!/usr/bin/env bash
# ==============================================================================
# run.sh - Runner script for Quickshell Floating LyricBar
# ==============================================================================

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export HOME="${HOME:-$(getent passwd "$(id -u)" | cut -d: -f6)}"
export PATH="${HOME}/.local/bin:/usr/local/bin:/usr/bin:/bin:${PATH}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

# Auto-detect Wayland socket if not already set or not pointing to a valid socket
if [[ -z "${WAYLAND_DISPLAY:-}" || ! -S "${XDG_RUNTIME_DIR}/${WAYLAND_DISPLAY}" ]]; then
    for sock in "${XDG_RUNTIME_DIR}"/wayland-[0-9]*; do
        if [[ -S "$sock" && "$sock" =~ /wayland-[0-9]+$ ]]; then
            export WAYLAND_DISPLAY="$(basename "$sock")"
            break
        fi
    done
    export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}"
fi

# Handle IPC passthrough directly
if [[ "${1:-}" == "ipc" ]]; then
    shift
    exec qs -c lyricbar ipc --any-display "$@"
fi

print_help() {
    echo "Usage: ./run.sh [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --demo, -t         Run in demo mode with synchronized test lyrics"
    echo "  --background, -b   Run detached in background"
    echo "  --kill, -k         Kill running lyricbar instance"
    echo "  ipc [COMMAND...]   Send IPC command to running LyricBar instance"
    echo "  --help, -h         Show this help message"
    echo ""
}

kill_instance() {
    echo "Stopping Quickshell LyricBar instances..."
    pkill -f "qs.*lyricbar" 2>/dev/null || true
    pkill -f "lyric_listener.py" 2>/dev/null || true
    echo "Done."
}

DEMO_FLAG=0
DAEMON_FLAG=0

for arg in "$@"; do
    case "$arg" in
        --demo|-t)
            DEMO_FLAG=1
            ;;
        --background|-b)
            DAEMON_FLAG=1
            ;;
        --kill|-k)
            kill_instance
            exit 0
            ;;
        --help|-h)
            print_help
            exit 0
            ;;
        *)
            echo "Unknown option: $arg"
            print_help
            exit 1
            ;;
    esac
done

if [ "$DEMO_FLAG" -eq 1 ]; then
    export QS_LYRIC_DEMO=1
    echo "Starting Quickshell Floating LyricBar in DEMO mode..."
else
    export QS_LYRIC_DEMO=0
    echo "Starting Quickshell Floating LyricBar (MPRIS mode)..."
fi

# If Wayland socket is not yet ready (e.g. cold system boot), wait up to 5s
WAIT_COUNT=0
while [[ ! -S "${XDG_RUNTIME_DIR}/${WAYLAND_DISPLAY}" && $WAIT_COUNT -lt 10 ]]; do
    sleep 0.5
    WAIT_COUNT=$((WAIT_COUNT + 1))
    for sock in "${XDG_RUNTIME_DIR}"/wayland-[0-9]*; do
        if [[ -S "$sock" && "$sock" =~ /wayland-[0-9]+$ ]]; then
            export WAYLAND_DISPLAY="$(basename "$sock")"
            break
        fi
    done
done

if [ "$DAEMON_FLAG" -eq 1 ]; then
    if pgrep -f "qs.*lyricbar" > /dev/null 2>&1; then
        echo "LyricBar is already running."
        exit 0
    fi
    nohup qs -c lyricbar > /dev/null 2>&1 &
    echo "LyricBar started in background (PID: $!)."
else
    exec qs -c lyricbar
fi
