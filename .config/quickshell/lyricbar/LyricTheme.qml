import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root

    // File paths
    readonly property string cacheThemePath: Quickshell.env("HOME") + "/.cache/43pr/quickshell-theme.json"
    readonly property string m3ThemePath: Quickshell.env("HOME") + "/.local/state/quickshell/user/generated/colors.json"
    readonly property string colorTxtPath: Quickshell.env("HOME") + "/.local/state/quickshell/user/generated/color.txt"

    // Base color properties with defaults matching system dark theme
    property color bg: "#0d0e13"
    property real bgAlpha: 0.55
    property color bgCard: "#1a1b21"
    property color text: "#e3e2e9"
    property color textDim: "#c5c6d0"
    property color textFaint: "#8f909a"
    property color accent: "#b4c5ff"
    property color accent2: "#c1c6dd"
    property color border: "#45464f"
    property color borderAccent: "#45464f"
    property color danger: "#ffb4ab"
    property color ok: "#e2bbdc"

    // Liquid Glass specific colors & effects (reactive bindings to base colors)
    readonly property color glassBg: Qt.rgba(bg.r, bg.g, bg.b, 0.42)
    readonly property color glassBgHover: Qt.rgba(bg.r, bg.g, bg.b, 0.56)
    readonly property color glassCard: Qt.rgba(bgCard.r, bgCard.g, bgCard.b, 0.48)
    readonly property color glassBorder: Qt.rgba(1.0, 1.0, 1.0, 0.16)
    readonly property color glassBorderHover: Qt.rgba(accent.r, accent.g, accent.b, 0.65)
    readonly property color glassHighlight: Qt.rgba(1.0, 1.0, 1.0, 0.22)
    readonly property color glassHighlightFaint: Qt.rgba(1.0, 1.0, 1.0, 0.08)
    readonly property color glassShadow: Qt.rgba(0.0, 0.0, 0.0, 0.45)

    // Typography
    property string fontFamily: "JetBrainsMono Nerd Font"
    property string iconFont: "JetBrainsMono Nerd Font"
    property int fontSizeMain: 12
    property int fontSizeSmall: 10
    property int fontSizeIcon: 13

    // Dimensions & Rounding
    property int cornerRadius: 20
    property int barHeight: 44
    property int pillHeight: 34

    // Animation Durations & Curves
    property int animFast: 150
    property int animMed: 350
    property int animSlow: 520

    // Cache of last loaded text to prevent redundant parsing
    property string lastCacheText: ""
    property string lastM3Text: ""

    // Primary: 43PR Quickshell Theme (~/.cache/43pr/quickshell-theme.json)
    FileView {
        id: cacheView
        path: root.cacheThemePath
        watchChanges: true
        onFileChanged: {
            this.reload();
            applyTimer.restart();
        }
        onLoadedChanged: {
            if (loaded) applyTimer.restart();
        }
    }

    // Secondary: Material3 Colors (~/.local/state/quickshell/user/generated/colors.json)
    FileView {
        id: m3View
        path: root.m3ThemePath
        watchChanges: true
        onFileChanged: {
            this.reload();
            applyTimer.restart();
        }
        onLoadedChanged: {
            if (loaded) applyTimer.restart();
        }
    }

    // Tertiary: Single Accent Color (~/.local/state/quickshell/user/generated/color.txt)
    FileView {
        id: colorTxtView
        path: root.colorTxtPath
        watchChanges: true
        onFileChanged: {
            this.reload();
            applyTimer.restart();
        }
    }

    // Debounced apply timer (ensures file is fully flushed before parsing)
    Timer {
        id: applyTimer
        interval: 60
        repeat: false
        running: false
        onTriggered: root.applyTheme()
    }

    // Watchdog timer: checks every 1.2s to guarantee synchronization even if inotify was unlinked by atomic file replacement
    Timer {
        id: watchdogTimer
        interval: 1200
        repeat: true
        running: true
        onTriggered: {
            cacheView.reload();
            m3View.reload();
            colorTxtView.reload();
            applyTimer.restart();
        }
    }

    function applyTheme() {
        const rawCache = cacheView.text();
        const rawM3 = m3View.text();

        // 1. Try 43pr quickshell-theme.json first
        if (rawCache && rawCache.trim().startsWith("{")) {
            if (rawCache !== root.lastCacheText) {
                root.lastCacheText = rawCache;
                root.parseTheme(rawCache);
                return;
            }
        }

        // 2. Fallback to Material 3 generated colors.json
        if (rawM3 && rawM3.trim().startsWith("{")) {
            if (rawM3 !== root.lastM3Text) {
                root.lastM3Text = rawM3;
                root.parseM3(rawM3);
                return;
            }
        }

        // 3. Accent color fallback from color.txt if available
        const rawColor = colorTxtView.text().trim();
        if (rawColor && rawColor.startsWith("#") && rawColor.length === 7) {
            if (root.accent.toString() !== rawColor) {
                root.accent = rawColor;
            }
        }
    }

    function parseTheme(jsonText) {
        if (!jsonText) return;
        try {
            const data = JSON.parse(jsonText);
            if (data.bg) root.bg = data.bg;
            if (data.bgAlpha !== undefined) root.bgAlpha = data.bgAlpha;
            if (data.bgCard) root.bgCard = data.bgCard;
            if (data.text) root.text = data.text;
            if (data.textDim) root.textDim = data.textDim;
            if (data.textFaint) root.textFaint = data.textFaint;
            if (data.accent) root.accent = data.accent;
            if (data.accent2) root.accent2 = data.accent2;
            if (data.border) root.border = data.border;
            if (data.borderAccent) root.borderAccent = data.borderAccent;
            if (data.danger) root.danger = data.danger;
            if (data.ok) root.ok = data.ok;
        } catch (e) {
            console.warn("[LyricTheme] JSON parse error:", e);
        }
    }

    function parseM3(jsonText) {
        if (!jsonText) return;
        try {
            const data = JSON.parse(jsonText);
            if (data.background) root.bg = data.background;
            if (data.primary) root.accent = data.primary;
            if (data.secondary) root.accent2 = data.secondary;
            if (data.on_surface) root.text = data.on_surface;
            if (data.on_surface_variant) root.textDim = data.on_surface_variant;
            if (data.outline) root.border = data.outline;
            if (data.outline_variant) root.borderAccent = data.outline_variant;
            if (data.error) root.danger = data.error;
            if (data.surface_container) root.bgCard = data.surface_container;
        } catch (e) {
            console.warn("[LyricTheme] M3 parse error:", e);
        }
    }

    function reloadAll() {
        cacheView.reload();
        m3View.reload();
        colorTxtView.reload();
        applyTimer.restart();
    }

    // IPC Handler to allow external scripts or Hyprland hooks to trigger instant theme reload
    IpcHandler {
        target: "lyrictheme"
        function reload(): void {
            root.reloadAll();
        }
    }

    Component.onCompleted: {
        cacheView.reload();
        m3View.reload();
        colorTxtView.reload();
        applyTimer.restart();
    }
}
