#!/usr/bin/env bash

is_running() {
    pgrep -f "owly receive" >/dev/null 2>&1
}

case "$1" in
    status)
        if is_running; then
            echo "active"
            exit 0
        else
            echo "inactive"
            exit 1
        fi
        ;;
    start)
        if is_running; then
            exit 0
        fi
        nohup owly radio up >/dev/null 2>&1 &
        
        # Wait up to 5s for awdl0
        for i in {1..10}; do
            if ip link show awdl0 >/dev/null 2>&1; then
                break
            fi
            sleep 0.5
        done
        
        nohup owly receive --accept --dir "$HOME/airdrop" >/dev/null 2>&1 &
        notify-send -a "AirDrop" "AirDrop (Owly) Aktif" "Siap menerima file di ~/airdrop (Wi-Fi router sementara offline)" -i preferences-system-network-sharing
        ;;
    stop)
        pkill -INT -f "owly receive" 2>/dev/null || true
        pkill -INT -f "owly radio up" 2>/dev/null || true
        sleep 0.5
        pkill -9 -f "owly receive" 2>/dev/null || true
        pkill -9 -f "owly radio up" 2>/dev/null || true
        # Reconnect Wi-Fi immediately
        nmcli device connect wlan0 2>/dev/null || true
        notify-send -a "AirDrop" "AirDrop (Owly) Nonaktif" "Receiver AirDrop dimatikan. Wi-Fi terhubung kembali." -i preferences-system-network-sharing
        ;;
    toggle)
        if is_running; then
            "$0" stop
        else
            "$0" start
        fi
        ;;
esac
