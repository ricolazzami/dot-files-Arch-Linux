#!/usr/bin/env python3
import sys
import os
import re
import json
import subprocess

HYPRIDLE_CONF = os.path.expanduser("~/.config/hypr/hypridle.conf")

DEFAULT_CONF = """$lock_cmd = hyprctl dispatch 'hl.dsp.global("quickshell:lock")' & pidof qs quickshell hyprlock || hyprlock
$suspend_cmd = systemctl suspend || loginctl suspend

general {
    lock_cmd = $lock_cmd
    before_sleep_cmd = loginctl lock-session
    after_sleep_cmd = hyprctl dispatch 'hl.dsp.dpms({ action = "enable" })' && hyprctl dispatch 'hl.dsp.global("quickshell:lockFocus")'
    inhibit_sleep = 3
}

listener {
    timeout = {lock_s}
    on-timeout = loginctl lock-session
}

listener {
    timeout = {dpms_s}
    on-timeout = hyprctl dispatch 'hl.dsp.dpms({ action = "disable" })'
    on-resume = hyprctl dispatch 'hl.dsp.dpms({ action = "enable" })'
}

listener {
    timeout = {suspend_s}
    on-timeout = $suspend_cmd
}
"""

def get_timeouts():
    lock_min = 5
    screen_off_min = 10
    suspend_min = 15
    if os.path.exists(HYPRIDLE_CONF):
        with open(HYPRIDLE_CONF, 'r') as f:
            content = f.read()
        
        # lock listener
        m_lock = re.search(r'listener\s*\{[^}]*timeout\s*=\s*(\d+)[^}]*loginctl lock-session', content, re.DOTALL)
        if m_lock:
            lock_min = max(0, round(int(m_lock.group(1)) / 60))

        # dpms listener
        m_dpms = re.search(r'listener\s*\{[^}]*timeout\s*=\s*(\d+)[^}]*dpms', content, re.DOTALL)
        if m_dpms:
            screen_off_min = max(0, round(int(m_dpms.group(1)) / 60))

        # suspend listener
        m_sus = re.search(r'listener\s*\{[^}]*timeout\s*=\s*(\d+)[^}]*suspend', content, re.DOTALL)
        if m_sus:
            suspend_min = max(0, round(int(m_sus.group(1)) / 60))

    return {
        "lock": lock_min,
        "screen_off": screen_off_min,
        "suspend": suspend_min
    }

def update_timeouts(lock_min, screen_off_min, suspend_min):
    lock_s = max(30, int(lock_min) * 60) if int(lock_min) > 0 else 999999
    dpms_s = max(30, int(screen_off_min) * 60) if int(screen_off_min) > 0 else 999999
    suspend_s = max(60, int(suspend_min) * 60) if int(suspend_min) > 0 else 999999

    new_content = f"""$lock_cmd = hyprctl dispatch 'hl.dsp.global("quickshell:lock")' & pidof qs quickshell hyprlock || hyprlock
$suspend_cmd = systemctl suspend || loginctl suspend

general {{
    lock_cmd = $lock_cmd
    before_sleep_cmd = loginctl lock-session
    after_sleep_cmd = hyprctl dispatch 'hl.dsp.dpms({{ action = "enable" }})' && hyprctl dispatch 'hl.dsp.global("quickshell:lockFocus")'
    inhibit_sleep = 3
}}

listener {{
    timeout = {lock_s} # {lock_min}mins
    on-timeout = loginctl lock-session
}}

listener {{
    timeout = {dpms_s} # {screen_off_min}mins
    on-timeout = hyprctl dispatch 'hl.dsp.dpms({{ action = "disable" }})'
    on-resume = hyprctl dispatch 'hl.dsp.dpms({{ action = "enable" }})'
}}

listener {{
    timeout = {suspend_s} # {suspend_min}mins
    on-timeout = $suspend_cmd
}}
"""
    with open(HYPRIDLE_CONF, 'w') as f:
        f.write(new_content)

    # restart hypridle
    subprocess.run(["killall", "-9", "hypridle"], stderr=subprocess.DEVNULL)
    subprocess.Popen(["hypridle"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "get":
        print(json.dumps(get_timeouts()))
    elif len(sys.argv) >= 5 and sys.argv[1] == "set":
        # python3 power_management.py set <lock> <screen_off> <suspend>
        lock = int(sys.argv[2])
        screen = int(sys.argv[3])
        suspend = int(sys.argv[4])
        update_timeouts(lock, screen, suspend)
        print(json.dumps({"success": True, "lock": lock, "screen_off": screen, "suspend": suspend}))
    else:
        print("Usage: power_management.py get | set <lock_min> <screen_off_min> <suspend_min>")
