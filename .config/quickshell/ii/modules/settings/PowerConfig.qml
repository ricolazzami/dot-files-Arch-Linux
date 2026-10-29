import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

ContentPage {
    id: root
    forceWidth: true

    property int lockTimeout: 5
    property int screenOffTimeout: 10
    property int suspendTimeout: 15
    property bool timeoutsLoaded: false

    Process {
        id: loadTimeoutsProc
        command: ["python3", `${Directories.scriptPath}/power/power_management.py`, "get"]
        stdout: SplitParser {
            onRead: data => {
                try {
                    let parsed = JSON.parse(data.trim());
                    if (parsed.screen_off !== undefined) root.screenOffTimeout = parsed.screen_off;
                    if (parsed.suspend !== undefined) root.suspendTimeout = parsed.suspend;
                    if (parsed.lock !== undefined) root.lockTimeout = parsed.lock;
                    root.timeoutsLoaded = true;
                } catch(e) {
                    console.log("Error reading power timeouts:", e);
                }
            }
        }
        Component.onCompleted: running = true
    }

    function loadTimeouts() {
        loadTimeoutsProc.running = false;
        loadTimeoutsProc.running = true;
    }

    function applyTimeouts() {
        if (!root.timeoutsLoaded) return;
        Quickshell.execDetached([
            "python3",
            `${Directories.scriptPath}/power/power_management.py`,
            "set",
            String(root.lockTimeout),
            String(root.screenOffTimeout),
            String(root.suspendTimeout)
        ]);
    }

    // 1. Live Battery & Power Overview
    ContentSection {
        icon: "battery_charging_full"
        title: Translation.tr("Power Status")

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 74
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer2

            RowLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 14

                MaterialSymbol {
                    text: Battery.isPluggedIn ? "power" : (Battery.isLow ? "battery_alert" : "battery_std")
                    iconSize: 32
                    color: Appearance.colors.colPrimary
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    StyledText {
                        font.bold: true
                        font.pixelSize: Appearance.font.pixelSize.normal
                        text: {
                            let status = Battery.isPluggedIn ? Translation.tr("Plugged in / Charging") : Translation.tr("On Battery");
                            let pct = Math.round(Battery.percentage * 100);
                            let rate = Battery.energyRate > 0 ? ` (${Battery.energyRate.toFixed(1)} W)` : "";
                            return `${status} • ${pct}%${rate}`;
                        }
                        color: Appearance.colors.colOnLayer2
                    }
                    StyledText {
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOutline
                        text: `${Translation.tr("Profile")}: ${PowerProfilesDaemon.displayName}`
                    }
                }

                RippleButton {
                    id: refreshBtn
                    implicitHeight: 38
                    implicitWidth: 110
                    buttonRadius: Appearance.rounding.small
                    colBackground: refreshBtn.down ? Appearance.colors.colPrimaryActive : (refreshBtn.hovered ? Appearance.colors.colPrimaryHover : Appearance.colors.colPrimary)
                    contentItem: RowLayout {
                        anchors.centerIn: parent
                        spacing: 6
                        MaterialSymbol {
                            text: "refresh"
                            iconSize: 18
                            color: Appearance.colors.colOnPrimary
                        }
                        StyledText {
                            text: Translation.tr("Refresh")
                            color: Appearance.colors.colOnPrimary
                            font.bold: true
                            font.pixelSize: Appearance.font.pixelSize.small
                        }
                    }
                    onClicked: {
                        PowerProfilesDaemon.refresh();
                        root.loadTimeouts();
                        Quickshell.execDetached([
                            "notify-send",
                            Translation.tr("Power Status"),
                            Translation.tr("Refreshed power status"),
                            "-i", "battery",
                            "-a", "Settings",
                            "--hint=int:transient:1"
                        ]);
                    }
                }
            }
        }
    }

    // 2. Power Profiles (Performance, Balanced, Power Saver)
    ContentSection {
        icon: "speed"
        title: Translation.tr("Power Mode")

        StyledText {
            Layout.fillWidth: true
            color: Appearance.colors.colOnSecondaryContainer
            font.pixelSize: Appearance.font.pixelSize.small
            text: Translation.tr("Select a power profile to optimize between performance and energy efficiency.")
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            // Performance Card
            RippleButton {
                id: perfBtn
                Layout.fillWidth: true
                Layout.preferredHeight: 90
                buttonRadius: Appearance.rounding.normal
                toggled: PowerProfilesDaemon.activeProfile === "performance"
                colBackground: toggled ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer2
                onClicked: PowerProfilesDaemon.setProfile("performance")

                contentItem: RowLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 12

                    MaterialSymbol {
                        text: "local_fire_department"
                        iconSize: 32
                        color: perfBtn.toggled ? Appearance.colors.colPrimary : Appearance.colors.colOnSecondaryContainer
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        StyledText {
                            text: Translation.tr("Performance")
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.bold: true
                            color: perfBtn.toggled ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer2
                        }
                        StyledText {
                            text: Translation.tr("Maximum speed & responsiveness")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: perfBtn.toggled ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOutline
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }
                    }

                    MaterialSymbol {
                        visible: perfBtn.toggled
                        text: "check_circle"
                        iconSize: 20
                        color: Appearance.colors.colPrimary
                    }
                }
            }

            // Balanced Card
            RippleButton {
                id: balancedBtn
                Layout.fillWidth: true
                Layout.preferredHeight: 90
                buttonRadius: Appearance.rounding.normal
                toggled: PowerProfilesDaemon.activeProfile === "balanced"
                colBackground: toggled ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer2
                onClicked: PowerProfilesDaemon.setProfile("balanced")

                contentItem: RowLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 12

                    MaterialSymbol {
                        text: "airwave"
                        iconSize: 32
                        color: balancedBtn.toggled ? Appearance.colors.colPrimary : Appearance.colors.colOnSecondaryContainer
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        StyledText {
                            text: Translation.tr("Balanced")
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.bold: true
                            color: balancedBtn.toggled ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer2
                        }
                        StyledText {
                            text: Translation.tr("Standard balance of battery and speed")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: balancedBtn.toggled ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOutline
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }
                    }

                    MaterialSymbol {
                        visible: balancedBtn.toggled
                        text: "check_circle"
                        iconSize: 20
                        color: Appearance.colors.colPrimary
                    }
                }
            }

            // Battery Saver Card
            RippleButton {
                id: saverBtn
                Layout.fillWidth: true
                Layout.preferredHeight: 90
                buttonRadius: Appearance.rounding.normal
                toggled: PowerProfilesDaemon.activeProfile === "power-saver"
                colBackground: toggled ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer2
                onClicked: PowerProfilesDaemon.setProfile("power-saver")

                contentItem: RowLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 12

                    MaterialSymbol {
                        text: "energy_savings_leaf"
                        iconSize: 32
                        color: saverBtn.toggled ? Appearance.colors.colPrimary : Appearance.colors.colOnSecondaryContainer
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        StyledText {
                            text: Translation.tr("Battery Saver")
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.bold: true
                            color: saverBtn.toggled ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer2
                        }
                        StyledText {
                            text: Translation.tr("Reduces power usage to extend battery")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: saverBtn.toggled ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOutline
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }
                    }

                    MaterialSymbol {
                        visible: saverBtn.toggled
                        text: "check_circle"
                        iconSize: 20
                        color: Appearance.colors.colPrimary
                    }
                }
            }
        }
    }

    // 3. Sleep & Suspend Idle Settings (Hypridle)
    ContentSection {
        icon: "bedtime"
        title: Translation.tr("Sleep & Idle Timeout")

        StyledText {
            Layout.fillWidth: true
            color: Appearance.colors.colOnSecondaryContainer
            font.pixelSize: Appearance.font.pixelSize.small
            text: Translation.tr("Adjust idle timeouts for locking the session, turning off screens, and system suspend.")
        }

        ConfigRow {
            uniform: true
            ConfigSpinBox {
                icon: "lock_clock"
                text: Translation.tr("Lock session (minutes)")
                value: root.lockTimeout
                from: 1
                to: 120
                stepSize: 1
                onValueChanged: {
                    if (root.lockTimeout !== value) {
                        root.lockTimeout = value;
                        root.applyTimeouts();
                    }
                }
            }
            ConfigSpinBox {
                icon: "desktop_access_disabled"
                text: Translation.tr("Turn off screen (minutes)")
                value: root.screenOffTimeout
                from: 1
                to: 180
                stepSize: 2
                onValueChanged: {
                    if (root.screenOffTimeout !== value) {
                        root.screenOffTimeout = value;
                        root.applyTimeouts();
                    }
                }
            }
        }

        ConfigRow {
            uniform: true
            ConfigSpinBox {
                icon: "mode_standby"
                text: Translation.tr("System suspend (minutes)")
                value: root.suspendTimeout
                from: 1
                to: 360
                stepSize: 5
                onValueChanged: {
                    if (root.suspendTimeout !== value) {
                        root.suspendTimeout = value;
                        root.applyTimeouts();
                    }
                }
            }
        }
    }

    // 4. Low Battery & Auto-Suspend Protections
    ContentSection {
        icon: "battery_alert"
        title: Translation.tr("Battery Protections")

        ConfigRow {
            uniform: false
            Layout.fillWidth: false
            ConfigSwitch {
                buttonIcon: "pause_circle"
                text: Translation.tr("Automatic suspend on low battery")
                checked: Config.options.battery.automaticSuspend
                onCheckedChanged: {
                    Config.options.battery.automaticSuspend = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Automatically puts system to sleep when battery drops below threshold")
                }
            }
            ConfigSpinBox {
                enabled: Config.options.battery.automaticSuspend
                text: Translation.tr("at")
                value: Config.options.battery.suspend
                from: 1
                to: 20
                stepSize: 1
                onValueChanged: {
                    Config.options.battery.suspend = value;
                }
            }
        }

        ConfigRow {
            uniform: true
            ConfigSpinBox {
                icon: "warning"
                text: Translation.tr("Low battery warning (%)")
                value: Config.options.battery.low
                from: 5
                to: 50
                stepSize: 5
                onValueChanged: {
                    Config.options.battery.low = value;
                }
            }
            ConfigSpinBox {
                icon: "dangerous"
                text: Translation.tr("Critical battery warning (%)")
                value: Config.options.battery.critical
                from: 2
                to: 25
                stepSize: 1
                onValueChanged: {
                    Config.options.battery.critical = value;
                }
            }
        }
    }

    // 5. Quick Power Actions
    ContentSection {
        icon: "power_settings_new"
        title: Translation.tr("Power Actions")

        Flow {
            Layout.fillWidth: true
            spacing: 8

            RippleButtonWithIcon {
                materialIcon: "bedtime"
                mainText: Translation.tr("Suspend Now")
                onClicked: {
                    Quickshell.execDetached(["systemctl", "suspend"]);
                }
            }

            RippleButtonWithIcon {
                materialIcon: "lock"
                mainText: Translation.tr("Lock Screen")
                onClicked: {
                    Quickshell.execDetached(["loginctl", "lock-session"]);
                }
            }

            RippleButtonWithIcon {
                materialIcon: "power_settings_new"
                mainText: Translation.tr("Shutdown")
                onClicked: {
                    Quickshell.execDetached(["systemctl", "poweroff"]);
                }
            }

            RippleButtonWithIcon {
                materialIcon: "restart_alt"
                mainText: Translation.tr("Restart")
                onClicked: {
                    Quickshell.execDetached(["systemctl", "reboot"]);
                }
            }
        }
    }
}
