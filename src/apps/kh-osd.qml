// On-screen display daemon — transient overlay for volume feedback.
//
// Daemon: quickshell -c kh-osd
//
// Reacts automatically to PipeWire default-sink volume/mute changes.
// IPC is available for testing or manual override:
//   qs ipc call osd showVolume <0–150>
//   qs ipc call osd showMuted
//
// This file owns: window, PipeWire bindings, IPC, dismiss timer, and fade animation.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pipewire

ShellRoot {
    id: root

    NixConfig { id: cfg }

    // Load the icon font directly from the nix-store path baked into NixConfig.
    // Avoids relying on the user's system fonts — Stylix sans-serif lacks the
    // Material Design PUA glyphs and Qt does not auto-fall-back to them.
    FontLoader {
        id: iconFont
        source: "file://" + cfg.iconFontFile
    }

    // ── PipeWire ──────────────────────────────────────────────────────────────
    PwObjectTracker { objects: [Pipewire.defaultAudioSink] }

    QtObject {
        id: audio
        readonly property var  sink:  Pipewire.defaultAudioSink
        readonly property bool valid: sink !== null && sink.audio !== null
        readonly property bool muted: valid && sink.audio.muted
        readonly property real vol:   valid ? sink.audio.volume : 0

        // Suppress the initial binding evaluation on startup.
        property bool ready: false
        Component.onCompleted: functionality.onAudioReady()

        onMutedChanged: functionality.onMutedChanged(muted)
        onVolChanged:   functionality.onVolumeChanged(vol)
    }

    // ── State ─────────────────────────────────────────────────────────────────
    QtObject {
        id: state
        property int    value: 0
        property string icon:  "volume"
    }

    // ── Functionality ─────────────────────────────────────────────────────────
    QtObject {
        id: functionality

        // Icon tiers split the configured max into thirds: low / medium / high.
        // Scales with volumeMax so the glyph tracks the bar's visual fill.
        readonly property real lowMax: cfg.volumeMax / 3
        readonly property real medMax: cfg.volumeMax * 2 / 3

        function iconForVol(vol: real): string {
            if (vol < lowMax) return "volume-low"
            if (vol < medMax) return "volume-medium"
            return "volume-high"
        }

        // ui only
        function onAudioReady(): void { audio.ready = true }
        // ui only
        function onVolumeChanged(vol: real): void {
            if (!audio.ready || audio.muted) return
            trigger(Math.round(vol * 100), iconForVol(vol))
        }
        // ui only
        function onMutedChanged(muted: bool): void {
            if (!audio.ready) return
            if (muted) trigger(0, "volume-mute")
            else       trigger(Math.round(audio.vol * 100), iconForVol(audio.vol))
        }
        // ipc only
        function showVolume(value: int): void { trigger(value, iconForVol(value / 100)) }
        // ipc only
        function showMuted(): void            { trigger(0, "volume-mute") }

        // ui only
        function trigger(value: int, icon: string): void {
            // Allow >100 so over-amplified levels display accurately; bar fill clamps separately.
            state.value = Math.max(0, Math.min(Math.round(cfg.volumeMax * 100), value))
            state.icon  = icon
            fadeAnim.stop()
            panel.opacity = 1.0
            dismissTimer.restart()
        }
    }

    // ── IPC ───────────────────────────────────────────────────────────────────
    IpcHandler {
        target: "osd"
        function showVolume(value: int): void { functionality.showVolume(value) }
        function showMuted(): void            { functionality.showMuted() }
    }

    // ── Dismiss timer — starts fade after 2 s of inactivity ──────────────────
    Timer {
        id: dismissTimer
        interval: 2000
        onTriggered: fadeAnim.start()
    }

    // ── Window ────────────────────────────────────────────────────────────────
    WlrLayershell {
        id: win
        // Always mapped; content visibility is gated by panel.opacity.
        visible: true
        layer: WlrLayer.Overlay
        keyboardFocus: WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore
        namespace: "kh-osd"

        // Empty input region — clicks pass through to windows underneath.
        mask: Region {}

        // Bottom-center: anchor bottom only; compositor centres horizontally.
        anchors.bottom: true
        margins.bottom: 80

        color: "transparent"
        implicitWidth: 320
        implicitHeight: 68

        // ── Panel — fade target ───────────────────────────────────────────────
        Item {
            id: panel
            anchors.fill: parent
            opacity: 0.0

            NumberAnimation {
                id: fadeAnim
                target: panel
                property: "opacity"
                to: 0.0
                duration: 350
                easing.type: Easing.InQuad
            }

            Rectangle {
                anchors.fill: parent
                color: cfg.color.base01
                opacity: 0.94
                radius: 14

                Row {
                    anchors.centerIn: parent
                    spacing: 14

                    // Icon — font.family comes from the FontLoader above so the glyph
                    // renders from the bundled nix-store font regardless of the user's
                    // system-wide font setup.
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        color: state.icon === "volume-mute" ? cfg.color.base03 : cfg.color.base05
                        font.family: iconFont.name
                        font.pixelSize: cfg.fontSize + 6
                        text: {
                            switch (state.icon) {
                                case "volume-mute":   return "\u{F075F}"  // mdi-volume-off
                                case "volume-low":    return "\u{F057F}"  // mdi-volume-low (one wave)
                                case "volume-medium": return "\u{F0580}"  // mdi-volume-medium (two waves)
                                default:              return "\u{F057E}"  // mdi-volume-high (three waves)
                            }
                        }
                    }

                    // Track + fill
                    Item {
                        width: 196
                        height: 10
                        anchors.verticalCenter: parent.verticalCenter

                        // Background track
                        Rectangle {
                            anchors.fill: parent
                            color: cfg.color.base02
                            radius: 5
                        }

                        // Fill — bar represents 0–volumeMax; maps linearly across the full track.
                        Rectangle {
                            width: Math.round(parent.width * (state.value / Math.round(cfg.volumeMax * 100)))
                            height: parent.height
                            color: state.icon === "volume-mute" ? cfg.color.base03 : cfg.color.base0D
                            radius: 5
                            Behavior on width {
                                NumberAnimation { duration: 80; easing.type: Easing.OutQuad }
                            }
                        }
                    }

                    // Percentage label
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        color: cfg.color.base04
                        font.family: cfg.fontFamily
                        font.pixelSize: cfg.fontSize - 1
                        text: state.icon === "volume-mute" ? "mute" : state.value + "%"
                        width: 42
                        horizontalAlignment: Text.AlignRight
                    }
                }
            }
        }
    }
}
