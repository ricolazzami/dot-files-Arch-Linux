import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import Quickshell
import Quickshell.Io

QuickToggleModel {
    id: root
    name: Translation.tr("AirDrop")
    statusText: toggled ? Translation.tr("Active") : Translation.tr("Inactive")
    toggled: false
    icon: "wifi_tethering"
    tooltipText: Translation.tr("AirDrop (Owly) | Klik untuk toggle, klik teks untuk buka Downloads")
    
    mainAction: () => {
        if (toggled) {
            root.toggled = false
            stopProc.running = true
        } else {
            root.toggled = true
            startProc.running = true
        }
    }

    altAction: () => {
        Quickshell.execDetached(["xdg-open", Directories.downloads])
    }

    Process {
        id: startProc
        command: ["/home/ricou/.local/bin/owly-toggle.sh", "start"]
        onExited: (exitCode, exitStatus) => {
            fetchActiveState.running = true
        }
    }

    Process {
        id: stopProc
        command: ["/home/ricou/.local/bin/owly-toggle.sh", "stop"]
        onExited: (exitCode, exitStatus) => {
            fetchActiveState.running = true
        }
    }

    Process {
        id: fetchActiveState
        running: true
        command: ["/home/ricou/.local/bin/owly-toggle.sh", "status"]
        stdout: StdioCollector {
            id: statusCollector
            onStreamFinished: {
                root.toggled = statusCollector.text.trim() === "active"
            }
        }
    }

    Timer {
        interval: 3000
        running: true
        repeat: true
        onTriggered: {
            if (!startProc.running && !stopProc.running) {
                fetchActiveState.running = true
            }
        }
    }
}
