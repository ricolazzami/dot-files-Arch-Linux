pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.services

Singleton {
    id: root

    property string activeProfile: "balanced"
    readonly property string icon: {
        switch(activeProfile) {
            case "performance": return "local_fire_department"
            case "power-saver": return "energy_savings_leaf"
            default: return "airwave"
        }
    }
    readonly property string displayName: {
        switch(activeProfile) {
            case "performance": return Translation.tr("Performance")
            case "power-saver": return Translation.tr("Power Saver")
            default: return Translation.tr("Balanced")
        }
    }

    Process {
        id: getProc
        command: ["powerprofilesctl", "get"]
        stdout: SplitParser {
            onRead: data => {
                let p = data.trim();
                if (p) root.activeProfile = p;
            }
        }
    }

    Process {
        id: setProc
        property string target: ""
        command: ["powerprofilesctl", "set", target]
        onExited: (code, status) => {
            refresh();
            Quickshell.execDetached([
                "notify-send",
                Translation.tr("Power Profile"),
                Translation.tr("Active profile: %1").arg(root.displayName),
                "-i", "battery",
                "-a", "Shell",
                "--hint=int:transient:1"
            ]);
        }
    }

    Timer {
        id: pollTimer
        interval: 1500
        running: true
        repeat: true
        onTriggered: {
            if (!setProc.running) {
                refresh();
            }
        }
    }

    function refresh() {
        getProc.running = false;
        getProc.running = true;
    }

    function setProfile(name) {
        root.activeProfile = name;
        setProc.target = name;
        setProc.running = false;
        setProc.running = true;
    }

    function cycleNext() {
        let next = "balanced";
        if (root.activeProfile === "balanced") {
            next = "performance";
        } else if (root.activeProfile === "performance") {
            next = "power-saver";
        } else {
            next = "balanced";
        }
        setProfile(next);
    }

    Component.onCompleted: {
        refresh();
    }
}
