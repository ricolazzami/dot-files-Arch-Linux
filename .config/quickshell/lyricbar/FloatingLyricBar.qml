pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

PanelWindow {
    id: root

    // ==========================================
    // 1. Theme & Liquid Glass Variables
    // ==========================================
    LyricTheme {
        id: theme
    }

    // ==========================================
    // 2. State, Customization & Media Properties
    // ==========================================
    property bool showing: true
    property bool compact: false
    property bool autoHideOnStop: true
    property bool demoMode: Quickshell.env("QS_LYRIC_DEMO") === "1"
    property bool settingsOpen: false
    property bool anchorTop: false
    property string horizontalAlign: "center" // "center", "left", "right"
    property int offsetY: 28                  // 16, 28, 44, 64
    property int marginSide: 32               // 16, 32, 48
    property bool showProgressBar: true
    property bool showArtistBadge: true
    property bool showPlayButton: true
    property bool showPulseDot: true
    property bool enableParallax: true
    property int fontSizeDelta: 0             // -2, 0, 2, 4
    property string bindToggle: "SUPER + Y"
    property string bindToggleMini: "SUPER + ALT + Y"
    property string bindToggleSettings: "SUPER + CTRL + Y"
    property string keybindStatusMsg: ""

    // 3D Parallax Tilt
    property real tiltX: 0.0
    property real tiltY: 0.0

    // MPRIS & Lyric Data
    property string activePlayer: ""
    property string activeLyric: ""
    property string displayedLyric: targetLyric
    property string nextLyric: ""
    property string trackTitle: ""
    property string trackArtist: ""
    property string trackAlbum: ""
    property string playbackStatus: "Stopped"
    property bool hasLyrics: false
    property real progress: 0.0
    property real position: 0.0
    property real duration: 0.0

    readonly property bool isPlaying: playbackStatus === "Playing"
    readonly property bool hasMedia: trackTitle !== "" && playbackStatus !== "Stopped"
    readonly property bool effectiveVisible: settingsOpen || (showing && (!autoHideOnStop || hasMedia))

    // Compute target text for dynamic measurement
    readonly property string targetLyric: {
        if (activeLyric !== "") return activeLyric;
        if (trackTitle !== "") {
            return trackArtist !== "" ? (trackArtist + " — " + trackTitle) : trackTitle;
        }
        return isPlaying ? "♪ ♪ ♪" : "LyricBar (No media playing)";
    }

    // Direct Media Control Methods
    function playPause(): void {
        if (root.activePlayer && root.activePlayer.length > 0) {
            Quickshell.execDetached(["bash", "-c", `playerctl -p "${root.activePlayer}" play-pause 2>/dev/null || playerctl play-pause`]);
        } else {
            Quickshell.execDetached(["playerctl", "play-pause"]);
        }
    }

    function next(): void {
        if (root.activePlayer && root.activePlayer.length > 0) {
            Quickshell.execDetached(["bash", "-c", `playerctl -p "${root.activePlayer}" next 2>/dev/null || playerctl next`]);
        } else {
            Quickshell.execDetached(["playerctl", "next"]);
        }
    }

    function prev(): void {
        if (root.activePlayer && root.activePlayer.length > 0) {
            Quickshell.execDetached(["bash", "-c", `playerctl -p "${root.activePlayer}" previous 2>/dev/null || playerctl previous`]);
        } else {
            Quickshell.execDetached(["playerctl", "previous"]);
        }
    }

    function changeVolume(deltaStr): void {
        if (root.activePlayer && root.activePlayer.length > 0) {
            Quickshell.execDetached(["bash", "-c", `playerctl -p "${root.activePlayer}" volume ${deltaStr} 2>/dev/null || playerctl volume ${deltaStr}`]);
        } else {
            Quickshell.execDetached(["playerctl", "volume", deltaStr]);
        }
    }

    // ==========================================
    // 3. Layer Shell Window Positioning & Click Mask
    // ==========================================
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    // HyprGlass layer integration
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell:lyricbar"
    WlrLayershell.keyboardFocus: root.settingsOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    // Click mask: Hanya area card aktif yang menangkap input mouse
    mask: Region {
        item: (cardWrapper.opacity > 0.02) ? cardWrapper : null
    }

    // ==========================================
    // 4. Global Shortcuts & IPC Handlers
    // ==========================================
    GlobalShortcut {
        name: "lyricBarToggle"
        description: "Toggle Quickshell Floating LyricBar"
        onPressed: root.showing = !root.showing
    }

    GlobalShortcut {
        name: "lyricBarToggleMini"
        description: "Toggle LyricBar compact mini-pill"
        onPressed: root.compact = !root.compact
    }

    GlobalShortcut {
        name: "lyricBarToggleSettings"
        description: "Toggle LyricBar settings modal"
        onPressed: root.settingsOpen = !root.settingsOpen
    }

    IpcHandler {
        target: "lyricbar"
        function toggle(): void { root.showing = !root.showing; }
        function show(): void { root.showing = true; }
        function hide(): void { root.showing = false; }
        function toggleMini(): void { root.compact = !root.compact; }
        function openSettings(): void { root.settingsOpen = true; }
        function closeSettings(): void { root.settingsOpen = false; }
        function toggleSettings(): void { root.settingsOpen = !root.settingsOpen; }
        function playPause(): void { root.playPause(); }
        function next(): void { root.next(); }
        function prev(): void { root.prev(); }
        function applyHyprlandKeybinds(): void { root.syncKeybinds(); }
        function setPosition(edge: string, align: string, offset: int): void {
            if (edge) root.anchorTop = (edge === "top");
            if (align) root.horizontalAlign = align;
            if (offset > 0) root.offsetY = offset;
            root.saveConfig();
        }
        function reloadConfig(): void { root.loadConfigFromDisk(); }
    }

    // Process to apply keybindings to Hyprland custom keybinds file
    Process {
        id: syncProcess
        function run(args) {
            if (running) running = false;
            command = args;
            running = true;
        }
        onExited: {
            root.keybindStatusMsg = "Keybinds Synced & Active!";
            statusClearTimer.restart();
        }
    }

    Timer {
        id: statusClearTimer
        interval: 3000
        repeat: false
        onTriggered: root.keybindStatusMsg = ""
    }

    function syncKeybinds() {
        root.saveConfig();
        const bToggle = root.bindToggle || "SUPER + Y";
        const bMini = root.bindToggleMini || "SUPER + ALT + Y";
        const bSettings = root.bindToggleSettings || "SUPER + CTRL + Y";

        const cmdScript = `
        KEYBIND_FILE="$HOME/.config/hypr/custom/keybinds.lua"
        mkdir -p "$(dirname "$KEYBIND_FILE")"
        touch "$KEYBIND_FILE"
        sed -i '/-- Quickshell LyricBar Keybindings/,/toggleSettings/d' "$KEYBIND_FILE" 2>/dev/null || true
        sed -i '/qs -c lyricbar.*toggle/d' "$KEYBIND_FILE" 2>/dev/null || true

        cat << 'EOF' >> "$KEYBIND_FILE"

-- Quickshell LyricBar Keybindings
hl.bind("${bToggle}", hl.dsp.exec_cmd("qs -c lyricbar ipc --any-display call lyricbar toggle"), { description = "LyricBar: Toggle visibility" })
hl.bind("${bMini}", hl.dsp.exec_cmd("qs -c lyricbar ipc --any-display call lyricbar toggleMini"), { description = "LyricBar: Toggle mini pill" })
hl.bind("${bSettings}", hl.dsp.exec_cmd("qs -c lyricbar ipc --any-display call lyricbar toggleSettings"), { description = "LyricBar: Toggle settings" })
EOF

        SIG=$(basename /run/user/$(id -u)/hypr/*_* 2>/dev/null | head -n 1 || echo "")
        if [ -n "$SIG" ]; then
            HYPRLAND_INSTANCE_SIGNATURE=$SIG hyprctl reload >/dev/null 2>&1 || true
        fi
        `;
        syncProcess.run(["bash", "-c", cmdScript]);
    }

    // ==========================================
    // 5. Config Persistence
    // ==========================================
    readonly property string userConfigPath: Quickshell.env("HOME") + "/.config/quickshell/lyricbar/config.json"

    FileView {
        id: userConfigFile
        path: root.userConfigPath
        watchChanges: true
        printErrors: false
        onLoaded: root.loadConfigFromDisk()
        onLoadedChanged: if (loaded) root.loadConfigFromDisk()
    }

    function loadConfigFromDisk() {
        try {
            const raw = userConfigFile.text();
            if (!raw || raw.trim().length === 0) return;
            const cfg = JSON.parse(raw);
            if (cfg.autoHideOnStop !== undefined) root.autoHideOnStop = Boolean(cfg.autoHideOnStop);
            if (cfg.anchorTop !== undefined) root.anchorTop = Boolean(cfg.anchorTop);
            if (cfg.horizontalAlign !== undefined) root.horizontalAlign = String(cfg.horizontalAlign);
            if (cfg.offsetY !== undefined) root.offsetY = Number(cfg.offsetY);
            if (cfg.marginSide !== undefined) root.marginSide = Number(cfg.marginSide);
            if (cfg.showProgressBar !== undefined) root.showProgressBar = Boolean(cfg.showProgressBar);
            if (cfg.showArtistBadge !== undefined) root.showArtistBadge = Boolean(cfg.showArtistBadge);
            if (cfg.showPlayButton !== undefined) root.showPlayButton = Boolean(cfg.showPlayButton);
            if (cfg.showPulseDot !== undefined) root.showPulseDot = Boolean(cfg.showPulseDot);
            if (cfg.enableParallax !== undefined) root.enableParallax = Boolean(cfg.enableParallax);
            if (cfg.fontSizeDelta !== undefined) root.fontSizeDelta = Number(cfg.fontSizeDelta);
            if (cfg.bindToggle !== undefined && cfg.bindToggle !== "") root.bindToggle = String(cfg.bindToggle);
            if (cfg.bindToggleMini !== undefined && cfg.bindToggleMini !== "") root.bindToggleMini = String(cfg.bindToggleMini);
            if (cfg.bindToggleSettings !== undefined && cfg.bindToggleSettings !== "") root.bindToggleSettings = String(cfg.bindToggleSettings);
            if (cfg.demoMode !== undefined && Quickshell.env("QS_LYRIC_DEMO") !== "1") root.demoMode = Boolean(cfg.demoMode);
        } catch(e) {}
    }

    function saveConfig() {
        const cfg = {
            "autoHideOnStop": root.autoHideOnStop,
            "anchorTop": root.anchorTop,
            "horizontalAlign": root.horizontalAlign,
            "offsetY": root.offsetY,
            "marginSide": root.marginSide,
            "showProgressBar": root.showProgressBar,
            "showArtistBadge": root.showArtistBadge,
            "showPlayButton": root.showPlayButton,
            "showPulseDot": root.showPulseDot,
            "enableParallax": root.enableParallax,
            "fontSizeDelta": root.fontSizeDelta,
            "bindToggle": root.bindToggle,
            "bindToggleMini": root.bindToggleMini,
            "bindToggleSettings": root.bindToggleSettings,
            "demoMode": root.demoMode
        };
        try {
            userConfigFile.setText(JSON.stringify(cfg, null, 2));
        } catch(e) {}
    }

    // ==========================================
    // 6. Lyric Listener Process (MPRIS & LRCLIB)
    // ==========================================
    readonly property string listenerScript: Quickshell.env("HOME") + "/.config/quickshell/lyricbar/lyric_listener.py"

    Process {
        id: lyricProcess
        command: [
            root.listenerScript,
            root.demoMode ? "--demo" : ""
        ].filter(arg => arg !== "")

        running: true

        stdout: SplitParser {
            onRead: data => {
                const line = data.trim();
                if (!line) return;
                try {
                    const info = JSON.parse(line);
                    root.activePlayer = info.player || "";
                    root.activeLyric = info.text || "";
                    root.nextLyric = info.next || "";
                    root.trackTitle = info.title || "";
                    root.trackArtist = info.artist || "";
                    root.trackAlbum = info.album || "";
                    root.playbackStatus = info.status || "Stopped";
                    root.hasLyrics = !!info.hasLyrics;
                    root.progress = info.progress || 0.0;
                    root.position = info.position || 0.0;
                    root.duration = info.duration || 0.0;
                } catch (e) {
                    root.activeLyric = line;
                }
            }
        }

        onExited: {
            if (root.showing) restartTimer.restart();
        }
    }

    Timer {
        id: restartTimer
        interval: 1200
        repeat: false
        onTriggered: {
            if (!lyricProcess.running) lyricProcess.running = true;
        }
    }

    // ==========================================
    // 7. Apple-Style Lyric Text Transition (Scale, Fade & Slide)
    // ==========================================
    onTargetLyricChanged: {
        if (targetLyric === displayedLyric) return;
        lyricTransition.restart();
    }

    SequentialAnimation {
        id: lyricTransition
        ParallelAnimation {
            NumberAnimation {
                target: lyricLabel
                property: "opacity"
                to: 0.0
                duration: 140
                easing.type: Easing.InQuad
            }
            NumberAnimation {
                target: lyricLabel
                property: "y"
                to: -9
                duration: 140
                easing.type: Easing.InQuad
            }
            NumberAnimation {
                target: lyricLabel
                property: "scale"
                to: 0.95
                duration: 140
                easing.type: Easing.InQuad
            }
        }
        ScriptAction {
            script: {
                root.displayedLyric = root.targetLyric;
                lyricLabel.y = 9;
                lyricLabel.scale = 0.95;
            }
        }
        ParallelAnimation {
            NumberAnimation {
                target: lyricLabel
                property: "opacity"
                to: 1.0
                duration: 280
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: lyricLabel
                property: "y"
                to: 0
                duration: 280
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: lyricLabel
                property: "scale"
                to: 1.0
                duration: 320
                easing.type: Easing.OutBack
                easing.overshoot: 1.06
            }
        }
    }

    // Offscreen Text Measure for Dynamic Width Calculation
    Text {
        id: lyricMeasure
        visible: false
        font.family: theme.fontFamily
        font.pixelSize: theme.fontSizeMain + root.fontSizeDelta
        font.bold: true
        renderType: Text.NativeRendering
        text: root.targetLyric
    }

    // Apple-style Glass Action Button with tactile micro-interaction
    component GlassActionBtn: Rectangle {
        id: gbtn
        property string icon: ""
        property color iconColor: theme.textDim
        property color hoverColor: theme.accent
        signal clicked()

        implicitWidth: 26
        implicitHeight: 26
        radius: 7
        color: gbtnMouse.pressed
               ? Qt.rgba(theme.text.r, theme.text.g, theme.text.b, 0.22)
               : (gbtnMouse.containsMouse ? Qt.rgba(theme.text.r, theme.text.g, theme.text.b, 0.12) : "transparent")

        scale: gbtnMouse.pressed ? 0.88 : (gbtnMouse.containsMouse ? 1.08 : 1.0)

        Behavior on color { ColorAnimation { duration: 160 } }
        Behavior on scale {
            NumberAnimation {
                duration: 200
                easing.type: Easing.OutBack
                easing.overshoot: 1.35
            }
        }

        Text {
            anchors.centerIn: parent
            text: gbtn.icon
            font.family: theme.iconFont
            font.pixelSize: 12
            renderType: Text.NativeRendering
            color: gbtnMouse.containsMouse ? gbtn.hoverColor : gbtn.iconColor
            Behavior on color { ColorAnimation { duration: 160 } }
        }

        MouseArea {
            id: gbtnMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: gbtn.clicked()
        }
    }

    // Interactive Pill Toggle / Select Button
    component GlassPillBtn: Rectangle {
        id: pbtn
        property string text: ""
        property bool selected: false
        signal clicked()

        implicitWidth: pbtnLabel.implicitWidth + 16
        implicitHeight: 24
        radius: 6
        color: pbtn.selected
               ? Qt.rgba(theme.accent.r, theme.accent.g, theme.accent.b, 0.28)
               : (pbtnMouse.containsMouse ? Qt.rgba(theme.bgCard.r, theme.bgCard.g, theme.bgCard.b, 0.7) : Qt.rgba(theme.bgCard.r, theme.bgCard.g, theme.bgCard.b, 0.35))
        border.color: pbtn.selected ? theme.accent : theme.glassBorder
        border.width: 1

        scale: pbtnMouse.pressed ? 0.94 : (pbtnMouse.containsMouse ? 1.02 : 1.0)
        Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
        Behavior on color { ColorAnimation { duration: 150 } }
        Behavior on border.color { ColorAnimation { duration: 150 } }

        Text {
            id: pbtnLabel
            anchors.centerIn: parent
            text: pbtn.text
            font.family: theme.fontFamily
            font.pixelSize: 10
            font.bold: pbtn.selected
            renderType: Text.NativeRendering
            color: pbtn.selected ? theme.accent : (pbtnMouse.containsMouse ? theme.text : theme.textDim)
        }

        MouseArea {
            id: pbtnMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: pbtn.clicked()
        }
    }

    // Editable Keybinding Input Field
    component GlassKeyInput: Rectangle {
        id: gki
        property alias text: input.text
        property string placeholder: ""
        signal committed(string val)

        implicitHeight: 24
        implicitWidth: 165
        radius: 6
        color: Qt.rgba(theme.bgCard.r, theme.bgCard.g, theme.bgCard.b, 0.55)
        border.color: input.activeFocus ? theme.accent : theme.glassBorder
        border.width: 1

        Behavior on border.color { ColorAnimation { duration: 160 } }

        TextInput {
            id: input
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            verticalAlignment: TextInput.AlignVCenter
            font.family: theme.fontFamily
            font.pixelSize: 10
            font.bold: true
            renderType: Text.NativeRendering
            color: theme.accent
            selectByMouse: true
            onEditingFinished: gki.committed(input.text.trim())
        }

        Text {
            anchors.fill: parent
            anchors.leftMargin: 8
            verticalAlignment: Text.AlignVCenter
            text: gki.placeholder
            font.family: theme.fontFamily
            font.pixelSize: 10
            renderType: Text.NativeRendering
            color: theme.textFaint
            visible: input.text.length === 0 && !input.activeFocus
        }
    }

    // Keyboard Key badge component for Settings Modal
    component KeyBadge: Rectangle {
        id: kbadge
        property string keyText: ""
        implicitWidth: klabel.implicitWidth + 14
        implicitHeight: 22
        radius: 6
        color: Qt.rgba(theme.bgCard.r, theme.bgCard.g, theme.bgCard.b, 0.6)
        border.color: theme.glassBorder
        border.width: 1

        Text {
            id: klabel
            anchors.centerIn: parent
            text: kbadge.keyText
            font.family: theme.fontFamily
            font.pixelSize: 10
            font.bold: true
            renderType: Text.NativeRendering
            color: theme.accent
        }
    }

    // ==========================================
    // 8. UNIFIED CONTAINER (Card Wrapper)
    // Apple-Style Entrance, Exit & Morphology Engine
    // ==========================================
    Item {
        id: cardWrapper

        width: Math.max(lyricCard.width, root.settingsOpen ? settingsCard.width : 0)
        height: lyricCard.height + (root.settingsOpen ? (settingsCard.height + 10) : 0)

        x: {
            if (root.horizontalAlign === "left") return root.marginSide;
            if (root.horizontalAlign === "right") return root.width - cardWrapper.width - root.marginSide;
            return (root.width - cardWrapper.width) / 2;
        }

        y: root.anchorTop ? root.offsetY : (root.height - cardWrapper.height - root.offsetY)

        readonly property bool isShown: root.effectiveVisible

        // Apple-style entrance / exit fluid spring state
        property real animY: isShown ? 0 : (root.anchorTop ? -50 : 50)
        property real animScale: isShown ? 1.0 : 0.86
        property real animOpacity: isShown ? 1.0 : 0.0

        scale: animScale
        opacity: animOpacity

        transform: Translate {
            y: cardWrapper.animY
        }

        visible: opacity > 0.001

        Behavior on animY {
            NumberAnimation {
                duration: cardWrapper.isShown ? 480 : 280
                easing.type: cardWrapper.isShown ? Easing.OutBack : Easing.InCubic
                easing.overshoot: 1.18
            }
        }
        Behavior on animScale {
            NumberAnimation {
                duration: cardWrapper.isShown ? 480 : 280
                easing.type: cardWrapper.isShown ? Easing.OutBack : Easing.InCubic
                easing.overshoot: 1.14
            }
        }
        Behavior on animOpacity {
            NumberAnimation {
                duration: cardWrapper.isShown ? 360 : 220
                easing.type: cardWrapper.isShown ? Easing.OutCubic : Easing.InQuad
            }
        }

        // ==========================================
        // 9. Settings Modal (Keybinds & Preferences)
        // ==========================================
        Rectangle {
            id: settingsCard
            visible: opacity > 0.001
            opacity: root.settingsOpen ? 1.0 : 0.0
            scale: root.settingsOpen ? 1.0 : 0.90

            property int currentTab: 0 // 0: Display & Pos, 1: Keybinds, 2: Styling & Effects

            width: 530
            height: 350
            radius: 18
            color: theme.glassBg
            border.color: theme.glassBorder
            border.width: 1
            clip: true
            focus: true

            x: {
                if (root.horizontalAlign === "left") return 0;
                if (root.horizontalAlign === "right") return cardWrapper.width - settingsCard.width;
                return (cardWrapper.width - settingsCard.width) / 2;
            }

            y: root.anchorTop ? (lyricCard.height + 10) : 0

            transform: Translate {
                y: root.settingsOpen ? 0 : (root.anchorTop ? -16 : 16)
                Behavior on y {
                    NumberAnimation {
                        duration: 380
                        easing.type: Easing.OutBack
                        easing.overshoot: 1.10
                    }
                }
            }

            Keys.onEscapePressed: {
                root.settingsOpen = false;
            }

            onVisibleChanged: {
                if (visible && root.settingsOpen) {
                    settingsCard.forceActiveFocus();
                }
            }

            Behavior on opacity { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
            Behavior on scale {
                NumberAnimation {
                    duration: 380
                    easing.type: Easing.OutBack
                    easing.overshoot: 1.14
                }
            }
            Behavior on color { ColorAnimation { duration: theme.animMed } }
            Behavior on border.color { ColorAnimation { duration: theme.animMed } }

            // Top Specular Highlight line
            Rectangle {
                anchors {
                    top: parent.top
                    left: parent.left
                    right: parent.right
                    margins: 1
                }
                height: 1
                color: theme.glassHighlight
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 10

                // Header Row (Title, Tab Buttons, Close)
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        text: "󰒓"
                        font.family: theme.iconFont
                        font.pixelSize: 15
                        renderType: Text.NativeRendering
                        color: theme.accent
                    }

                    Text {
                        text: "LyricBar Settings"
                        font.family: theme.fontFamily
                        font.pixelSize: 12
                        font.bold: true
                        renderType: Text.NativeRendering
                        color: theme.text
                    }

                    Item { Layout.fillWidth: true }

                    // Segmented Tab Bar
                    Row {
                        spacing: 4
                        Layout.alignment: Qt.AlignVCenter

                        GlassPillBtn {
                            text: "󰒓 Display"
                            selected: settingsCard.currentTab === 0
                            onClicked: settingsCard.currentTab = 0
                        }
                        GlassPillBtn {
                            text: "󰌌 Keybinds"
                            selected: settingsCard.currentTab === 1
                            onClicked: settingsCard.currentTab = 1
                        }
                        GlassPillBtn {
                            text: "󰏘 Style"
                            selected: settingsCard.currentTab === 2
                            onClicked: settingsCard.currentTab = 2
                        }
                    }

                    GlassActionBtn {
                        icon: "󰅖"
                        hoverColor: theme.danger
                        onClicked: root.settingsOpen = false
                    }
                }

                // Top Separator line
                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: Qt.rgba(theme.border.r, theme.border.g, theme.border.b, 0.4)
                }

                // Tab Content Stack
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    // ==========================================
                    // TAB 0: DISPLAY & POSITION
                    // ==========================================
                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 8
                        visible: opacity > 0.001
                        opacity: settingsCard.currentTab === 0 ? 1.0 : 0.0
                        Behavior on opacity { NumberAnimation { duration: 200 } }

                        // Row: Screen Edge
                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: "Screen Edge"
                                font.family: theme.fontFamily
                                font.pixelSize: 11
                                color: theme.text
                                renderType: Text.NativeRendering
                            }
                            Item { Layout.fillWidth: true }
                            GlassPillBtn {
                                text: "󰁅 Bottom"
                                selected: !root.anchorTop
                                onClicked: { root.anchorTop = false; root.saveConfig(); }
                            }
                            GlassPillBtn {
                                text: "󰁝 Top"
                                selected: root.anchorTop
                                onClicked: { root.anchorTop = true; root.saveConfig(); }
                            }
                        }

                        // Row: Horizontal Alignment
                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: "Alignment"
                                font.family: theme.fontFamily
                                font.pixelSize: 11
                                color: theme.text
                                renderType: Text.NativeRendering
                            }
                            Item { Layout.fillWidth: true }
                            GlassPillBtn {
                                text: "Left"
                                selected: root.horizontalAlign === "left"
                                onClicked: { root.horizontalAlign = "left"; root.saveConfig(); }
                            }
                            GlassPillBtn {
                                text: "Center"
                                selected: root.horizontalAlign === "center"
                                onClicked: { root.horizontalAlign = "center"; root.saveConfig(); }
                            }
                            GlassPillBtn {
                                text: "Right"
                                selected: root.horizontalAlign === "right"
                                onClicked: { root.horizontalAlign = "right"; root.saveConfig(); }
                            }
                        }

                        // Row: Vertical Margin Offset
                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: "Edge Offset (Y)"
                                font.family: theme.fontFamily
                                font.pixelSize: 11
                                color: theme.text
                                renderType: Text.NativeRendering
                            }
                            Item { Layout.fillWidth: true }
                            GlassPillBtn {
                                text: "16px"
                                selected: root.offsetY === 16
                                onClicked: { root.offsetY = 16; root.saveConfig(); }
                            }
                            GlassPillBtn {
                                text: "28px"
                                selected: root.offsetY === 28
                                onClicked: { root.offsetY = 28; root.saveConfig(); }
                            }
                            GlassPillBtn {
                                text: "44px"
                                selected: root.offsetY === 44
                                onClicked: { root.offsetY = 44; root.saveConfig(); }
                            }
                            GlassPillBtn {
                                text: "64px"
                                selected: root.offsetY === 64
                                onClicked: { root.offsetY = 64; root.saveConfig(); }
                            }
                        }

                        // Row: Duration Progress Bar
                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: "Music Duration Bar"
                                font.family: theme.fontFamily
                                font.pixelSize: 11
                                color: theme.text
                                renderType: Text.NativeRendering
                            }
                            Item { Layout.fillWidth: true }
                            GlassPillBtn {
                                text: "Show"
                                selected: root.showProgressBar
                                onClicked: { root.showProgressBar = true; root.saveConfig(); }
                            }
                            GlassPillBtn {
                                text: "Hide"
                                selected: !root.showProgressBar
                                onClicked: { root.showProgressBar = false; root.saveConfig(); }
                            }
                        }

                        // Row: Show/Hide Components
                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: "Capsule Elements"
                                font.family: theme.fontFamily
                                font.pixelSize: 11
                                color: theme.text
                                renderType: Text.NativeRendering
                            }
                            Item { Layout.fillWidth: true }
                            GlassPillBtn {
                                text: "Play/Disc: " + (root.showPlayButton ? "ON" : "OFF")
                                selected: root.showPlayButton
                                onClicked: { root.showPlayButton = !root.showPlayButton; root.saveConfig(); }
                            }
                            GlassPillBtn {
                                text: "Artist: " + (root.showArtistBadge ? "ON" : "OFF")
                                selected: root.showArtistBadge
                                onClicked: { root.showArtistBadge = !root.showArtistBadge; root.saveConfig(); }
                            }
                            GlassPillBtn {
                                text: "Pulse: " + (root.showPulseDot ? "ON" : "OFF")
                                selected: root.showPulseDot
                                onClicked: { root.showPulseDot = !root.showPulseDot; root.saveConfig(); }
                            }
                        }
                    }

                    // ==========================================
                    // TAB 1: KEYBINDINGS & SHORTCUTS
                    // ==========================================
                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 8
                        visible: opacity > 0.001
                        opacity: settingsCard.currentTab === 1 ? 1.0 : 0.0
                        Behavior on opacity { NumberAnimation { duration: 200 } }

                        // Row: Toggle Visibility
                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: "Toggle LyricBar"
                                font.family: theme.fontFamily
                                font.pixelSize: 11
                                color: theme.text
                                renderType: Text.NativeRendering
                            }
                            Item { Layout.fillWidth: true }
                            GlassKeyInput {
                                text: root.bindToggle
                                placeholder: "e.g. SUPER + Y"
                                onCommitted: val => { if (val) { root.bindToggle = val; root.saveConfig(); } }
                            }
                        }

                        // Row: Compact Mini-Pill
                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: "Compact Mini-Pill"
                                font.family: theme.fontFamily
                                font.pixelSize: 11
                                color: theme.text
                                renderType: Text.NativeRendering
                            }
                            Item { Layout.fillWidth: true }
                            GlassKeyInput {
                                text: root.bindToggleMini
                                placeholder: "e.g. SUPER + ALT + Y"
                                onCommitted: val => { if (val) { root.bindToggleMini = val; root.saveConfig(); } }
                            }
                        }

                        // Row: Settings Modal
                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: "Open / Close Settings"
                                font.family: theme.fontFamily
                                font.pixelSize: 11
                                color: theme.text
                                renderType: Text.NativeRendering
                            }
                            Item { Layout.fillWidth: true }
                            GlassKeyInput {
                                text: root.bindToggleSettings
                                placeholder: "e.g. SUPER + CTRL + Y"
                                onCommitted: val => { if (val) { root.bindToggleSettings = val; root.saveConfig(); } }
                            }
                        }

                        // Row: Mouse Gestures
                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: "Mouse Shortcuts"
                                font.family: theme.fontFamily
                                font.pixelSize: 11
                                color: theme.textDim
                                renderType: Text.NativeRendering
                            }
                            Item { Layout.fillWidth: true }
                            KeyBadge { keyText: "Wheel: Vol • R-Click: Next • Mid-Click: Prev" }
                        }

                        // Row: Keybind Actions
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            GlassPillBtn {
                                text: "Reset Defaults"
                                onClicked: {
                                    root.bindToggle = "SUPER + Y";
                                    root.bindToggleMini = "SUPER + ALT + Y";
                                    root.bindToggleSettings = "SUPER + CTRL + Y";
                                    root.saveConfig();
                                }
                            }
                            Item { Layout.fillWidth: true }
                            GlassPillBtn {
                                text: root.keybindStatusMsg !== "" ? ("󰄬 " + root.keybindStatusMsg) : "󰁯 Save & Sync Hyprland"
                                selected: true
                                onClicked: root.syncKeybinds()
                            }
                        }
                    }

                    // ==========================================
                    // TAB 2: STYLING & BEHAVIOR
                    // ==========================================
                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 8
                        visible: opacity > 0.001
                        opacity: settingsCard.currentTab === 2 ? 1.0 : 0.0
                        Behavior on opacity { NumberAnimation { duration: 200 } }

                        // Row: Lyric Font Size
                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: "Lyric Font Size"
                                font.family: theme.fontFamily
                                font.pixelSize: 11
                                color: theme.text
                                renderType: Text.NativeRendering
                            }
                            Item { Layout.fillWidth: true }
                            GlassPillBtn {
                                text: "Small (10px)"
                                selected: root.fontSizeDelta === -2
                                onClicked: { root.fontSizeDelta = -2; root.saveConfig(); }
                            }
                            GlassPillBtn {
                                text: "Normal (12px)"
                                selected: root.fontSizeDelta === 0
                                onClicked: { root.fontSizeDelta = 0; root.saveConfig(); }
                            }
                            GlassPillBtn {
                                text: "Large (14px)"
                                selected: root.fontSizeDelta === 2
                                onClicked: { root.fontSizeDelta = 2; root.saveConfig(); }
                            }
                            GlassPillBtn {
                                text: "XL (16px)"
                                selected: root.fontSizeDelta === 4
                                onClicked: { root.fontSizeDelta = 4; root.saveConfig(); }
                            }
                        }

                        // Row: Auto-Hide
                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: "Auto-Hide on Stop"
                                font.family: theme.fontFamily
                                font.pixelSize: 11
                                color: theme.text
                                renderType: Text.NativeRendering
                            }
                            Item { Layout.fillWidth: true }
                            GlassPillBtn {
                                text: "Enabled"
                                selected: root.autoHideOnStop
                                onClicked: { root.autoHideOnStop = true; root.saveConfig(); }
                            }
                            GlassPillBtn {
                                text: "Disabled"
                                selected: !root.autoHideOnStop
                                onClicked: { root.autoHideOnStop = false; root.saveConfig(); }
                            }
                        }

                        // Row: 3D Parallax Tilt
                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: "3D Parallax Tilt"
                                font.family: theme.fontFamily
                                font.pixelSize: 11
                                color: theme.text
                                renderType: Text.NativeRendering
                            }
                            Item { Layout.fillWidth: true }
                            GlassPillBtn {
                                text: "Enabled"
                                selected: root.enableParallax
                                onClicked: { root.enableParallax = true; root.saveConfig(); }
                            }
                            GlassPillBtn {
                                text: "Disabled"
                                selected: !root.enableParallax
                                onClicked: { root.enableParallax = false; root.saveConfig(); }
                            }
                        }

                        // Row: Demo Simulation Mode
                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: "Demo Mode (Mock LRC)"
                                font.family: theme.fontFamily
                                font.pixelSize: 11
                                color: theme.text
                                renderType: Text.NativeRendering
                            }
                            Item { Layout.fillWidth: true }
                            GlassPillBtn {
                                text: "Active"
                                selected: root.demoMode
                                onClicked: {
                                    root.demoMode = true;
                                    lyricProcess.running = false;
                                    restartTimer.restart();
                                    root.saveConfig();
                                }
                            }
                            GlassPillBtn {
                                text: "Off"
                                selected: !root.demoMode
                                onClicked: {
                                    root.demoMode = false;
                                    lyricProcess.running = false;
                                    restartTimer.restart();
                                    root.saveConfig();
                                }
                            }
                        }
                    }
                }
            }
        }

        // ==========================================
        // 10. UNIFIED MORPHING CAPSULE (Liquid Glass Card)
        // Seamlessly morphs between Full Lyric Bar and Compact Mini-Pill
        // ==========================================
        Rectangle {
            id: lyricCard

            // Computed content width for dynamic content-driven sizing
            readonly property real fullContentWidth: {
                const padding = 28;
                const playWidth = (root.showPlayButton ? (28 + cardLayout.spacing) : 0);
                const artistWidth = (root.showArtistBadge && root.trackArtist !== "" ? (artistBadge.implicitWidth + cardLayout.spacing) : 0);
                const textWidth = Math.max(120, Math.min(460, lyricMeasure.implicitWidth + 12));
                const pulseWidth = (root.showPulseDot && root.hasLyrics && root.isPlaying ? (8 + cardLayout.spacing) : 0);
                const actionsWidth = 74 + cardLayout.spacing;
                return padding + playWidth + artistWidth + textWidth + pulseWidth + actionsWidth;
            }

            readonly property real targetWidth: root.compact ? (theme.pillHeight + 10) : Math.max(300, Math.min(780, fullContentWidth))
            readonly property real targetHeight: root.compact ? theme.pillHeight : theme.barHeight
            readonly property real targetRadius: root.compact ? (targetHeight / 2) : theme.cornerRadius

            width: targetWidth
            implicitWidth: targetWidth
            height: targetHeight
            radius: targetRadius

            x: {
                if (root.horizontalAlign === "left") return 0;
                if (root.horizontalAlign === "right") return cardWrapper.width - lyricCard.width;
                return (cardWrapper.width - lyricCard.width) / 2;
            }

            y: root.anchorTop ? 0 : (cardWrapper.height - lyricCard.height)

            // Apple Dynamic Island fluid spring morphology
            Behavior on width {
                NumberAnimation {
                    duration: 460
                    easing.type: Easing.OutBack
                    easing.overshoot: 1.08
                }
            }
            Behavior on height {
                NumberAnimation {
                    duration: 380
                    easing.type: Easing.OutBack
                    easing.overshoot: 1.12
                }
            }
            Behavior on radius {
                NumberAnimation {
                    duration: 380
                    easing.type: Easing.OutCubic
                }
            }

            // ==========================================
            // LIQUID GLASS VISUAL STYLING
            // ==========================================
            color: (cardMouseArea.containsMouse || miniArea.containsMouse) ? theme.glassBgHover : theme.glassBg
            clip: true

            Behavior on color { ColorAnimation { duration: theme.animMed } }

            // Dual Border: Subtle glass rim + Accent hover glow
            border.color: (cardMouseArea.containsMouse || miniArea.containsMouse) ? theme.glassBorderHover : theme.glassBorder
            border.width: 1

            Behavior on border.color { ColorAnimation { duration: theme.animMed } }

            // Top Specular Highlight (Physical Glass Refraction Edge)
            Rectangle {
                anchors.top: parent.top
                anchors.topMargin: 1
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.max(0, parent.width - (root.compact ? 12 : 24))
                height: 1
                radius: 1
                color: (cardMouseArea.containsMouse || miniArea.containsMouse) ? theme.glassHighlight : theme.glassHighlightFaint
                Behavior on color { ColorAnimation { duration: theme.animMed } }
                Behavior on width { NumberAnimation { duration: 380; easing.type: Easing.OutCubic } }
            }

            // 3D Parallax Tilt Effect on Hover
            transform: [
                Rotation {
                    origin.x: lyricCard.width / 2
                    origin.y: lyricCard.height / 2
                    axis { x: 1; y: 0; z: 0 }
                    angle: root.enableParallax ? root.tiltX : 0.0
                    Behavior on angle { NumberAnimation { duration: theme.animMed; easing.type: Easing.OutCubic } }
                },
                Rotation {
                    origin.x: lyricCard.width / 2
                    origin.y: lyricCard.height / 2
                    axis { x: 0; y: 1; z: 0 }
                    angle: root.enableParallax ? root.tiltY : 0.0
                    Behavior on angle { NumberAnimation { duration: theme.animMed; easing.type: Easing.OutCubic } }
                }
            ]

            // ==========================================
            // LAYER A: COMPACT MODE CONTENT (Music Note Disc)
            // ==========================================
            Item {
                id: compactLayer
                anchors.fill: parent
                opacity: root.compact ? 1.0 : 0.0
                scale: root.compact ? 1.0 : 0.65
                visible: opacity > 0.01

                Behavior on opacity {
                    NumberAnimation {
                        duration: root.compact ? 280 : 160
                        easing.type: root.compact ? Easing.OutCubic : Easing.InQuad
                    }
                }
                Behavior on scale {
                    NumberAnimation {
                        duration: 380
                        easing.type: Easing.OutBack
                        easing.overshoot: 1.18
                    }
                }

                Text {
                    anchors.centerIn: parent
                    font.family: theme.iconFont
                    font.pixelSize: theme.fontSizeIcon
                    renderType: Text.NativeRendering
                    color: root.isPlaying ? theme.accent : theme.textDim
                    text: "󰎆" // Music note icon
                    Behavior on color { ColorAnimation { duration: theme.animFast } }

                    // Subtle breathing pulse when music is playing
                    SequentialAnimation on scale {
                        running: root.compact && root.isPlaying
                        loops: Animation.Infinite
                        NumberAnimation { from: 1.0; to: 1.12; duration: 900; easing.type: Easing.InOutSine }
                        NumberAnimation { from: 1.12; to: 1.0; duration: 900; easing.type: Easing.InOutSine }
                    }
                }

                MouseArea {
                    id: miniArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: mouse => {
                        if (mouse.button === Qt.RightButton) {
                            root.playPause();
                        } else {
                            root.compact = false;
                        }
                    }
                }
            }

            // ==========================================
            // LAYER B: FULL BAR CONTENT (Lyrics & Controls)
            // ==========================================
            Item {
                id: fullLayer
                anchors.fill: parent
                opacity: root.compact ? 0.0 : 1.0
                scale: root.compact ? 0.85 : 1.0
                visible: opacity > 0.01

                Behavior on opacity {
                    NumberAnimation {
                        duration: root.compact ? 180 : 300
                        easing.type: root.compact ? Easing.InQuad : Easing.OutCubic
                    }
                }
                Behavior on scale {
                    NumberAnimation {
                        duration: 360
                        easing.type: Easing.OutBack
                        easing.overshoot: 1.12
                    }
                }

                // Mini Progress Bar at bottom
                Rectangle {
                    id: progressBar
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    height: 2
                    radius: 1
                    color: Qt.rgba(theme.accent.r, theme.accent.g, theme.accent.b, 0.45)
                    width: Math.max(0, (lyricCard.width - 24) * Math.min(1.0, Math.max(0.0, root.progress)))
                    visible: root.showProgressBar && root.isPlaying && root.duration > 0 && !root.compact

                    Behavior on width { NumberAnimation { duration: 180 } }
                    Behavior on color { ColorAnimation { duration: theme.animMed } }
                }

                // MouseArea for interactivity, parallax, and playerctl shortcuts
                MouseArea {
                    id: cardMouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: !root.compact
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton

                    onPositionChanged: mouse => {
                        if (!root.enableParallax) {
                            root.tiltX = 0;
                            root.tiltY = 0;
                            return;
                        }
                        const nx = (mouse.x / lyricCard.width) - 0.5;
                        const ny = (mouse.y / lyricCard.height) - 0.5;
                        root.tiltX = -ny * 7;
                        root.tiltY = nx * 7;
                    }

                    onExited: {
                        root.tiltX = 0;
                        root.tiltY = 0;
                    }

                    onClicked: mouse => {
                        if (mouse.button === Qt.MiddleButton) {
                            root.prev();
                        } else if (mouse.button === Qt.RightButton) {
                            root.next();
                        }
                    }

                    onWheel: wheel => {
                        if (wheel.angleDelta.y > 0) {
                            root.changeVolume("0.05+");
                        } else if (wheel.angleDelta.y < 0) {
                            root.changeVolume("0.05-");
                        }
                    }
                }

                // Card Content Row Layout
                RowLayout {
                    id: cardLayout
                    anchors.centerIn: parent
                    spacing: 8

                    // 1. Play / Pause & Disc Button with Apple-style tactile spring
                    Rectangle {
                        id: playBtn
                        visible: root.showPlayButton
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: 28
                        implicitHeight: 28
                        radius: 14
                        color: Qt.rgba(theme.accent.r, theme.accent.g, theme.accent.b, playArea.containsMouse ? 0.32 : 0.16)

                        scale: playArea.pressed ? 0.90 : (playArea.containsMouse ? 1.08 : 1.0)

                        Behavior on color { ColorAnimation { duration: theme.animFast } }
                        Behavior on scale {
                            NumberAnimation {
                                duration: 220
                                easing.type: Easing.OutBack
                                easing.overshoot: 1.30
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            font.family: theme.iconFont
                            font.pixelSize: theme.fontSizeIcon
                            renderType: Text.NativeRendering
                            color: theme.accent
                            text: root.isPlaying ? "󰏤" : "󰐊" // Pause / Play icon
                            Behavior on color { ColorAnimation { duration: theme.animFast } }
                        }

                        MouseArea {
                            id: playArea
                            anchors.fill: parent
                            hoverEnabled: true
                            preventStealing: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.playPause()
                        }
                    }

                    // 2. Artist Badge (Themed Glass Pill)
                    Rectangle {
                        id: artistBadge
                        visible: root.showArtistBadge && root.trackArtist !== ""
                        Layout.alignment: Qt.AlignVCenter
                        implicitHeight: 22
                        implicitWidth: artistText.implicitWidth + 14
                        radius: 6
                        color: theme.glassCard
                        border.color: theme.border
                        border.width: 1

                        Behavior on color { ColorAnimation { duration: theme.animMed } }
                        Behavior on border.color { ColorAnimation { duration: theme.animMed } }

                        Text {
                            id: artistText
                            anchors.centerIn: parent
                            font.family: theme.fontFamily
                            font.pixelSize: theme.fontSizeSmall
                            font.bold: true
                            renderType: Text.NativeRendering
                            color: theme.textDim
                            text: root.trackArtist
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            Behavior on color { ColorAnimation { duration: theme.animMed } }
                        }
                    }

                    // 3. Divider Dot
                    Rectangle {
                        visible: root.showArtistBadge && root.trackArtist !== ""
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: 3
                        implicitHeight: 3
                        radius: 1.5
                        color: theme.textFaint
                    }

                    // 4. Live Lyric Line Container (High Legibility & Smooth Transition)
                    Item {
                        id: lyricContainer
                        Layout.alignment: Qt.AlignVCenter
                        Layout.fillWidth: true
                        implicitHeight: 24
                        implicitWidth: Math.min(460, lyricLabel.implicitWidth)
                        clip: true

                        Text {
                            id: lyricLabel
                            anchors.centerIn: parent
                            renderType: Text.NativeRendering
                            font.family: theme.fontFamily
                            font.pixelSize: theme.fontSizeMain + root.fontSizeDelta
                            font.bold: true
                            // Contrast outline shadow for crisp legibility over any wallpaper
                            style: Text.Outline
                            styleColor: Qt.rgba(0.0, 0.0, 0.0, 0.55)
                            color: root.activeLyric !== "" ? theme.text : theme.accent2
                            text: root.displayedLyric
                            elide: Text.ElideRight
                            maximumLineCount: 1

                            Behavior on color { ColorAnimation { duration: theme.animMed } }
                        }
                    }

                    // 5. Synced Lyrics Pulse Indicator
                    Rectangle {
                        visible: root.showPulseDot && root.hasLyrics && root.isPlaying
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: 6
                        implicitHeight: 6
                        radius: 3
                        color: theme.accent

                        Behavior on color { ColorAnimation { duration: theme.animFast } }

                        SequentialAnimation on opacity {
                            running: root.showPulseDot && root.hasLyrics && root.isPlaying
                            loops: Animation.Infinite
                            NumberAnimation { from: 0.35; to: 1.0; duration: 650; easing.type: Easing.InOutSine }
                            NumberAnimation { from: 1.0; to: 0.35; duration: 650; easing.type: Easing.InOutSine }
                        }
                    }

                    // 6. Action Buttons (Settings, Minimize & Close)
                    Row {
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 2

                        GlassActionBtn {
                            icon: "󰒓" // Settings
                            hoverColor: theme.accent
                            onClicked: root.settingsOpen = !root.settingsOpen
                        }

                        GlassActionBtn {
                            icon: "󰍹" // Compress / Pill
                            onClicked: root.compact = true
                        }

                        GlassActionBtn {
                            icon: "󰅖" // Close / X
                            hoverColor: theme.danger
                            onClicked: root.showing = false
                        }
                    }
                }
            }
        }
    }
}
