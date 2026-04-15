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
        Component.onCompleted: ready = true

        onMutedChanged: if (ready) functionality.onMutedChanged(muted)
        onVolChanged:   if (ready && !muted) functionality.onVolumeChanged(vol)
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

        // ui only
        function onVolumeChanged(vol: real): void {
            trigger(Math.round(vol * 100), vol < 0.15 ? "volume-low" : "volume")
        }
        // ui only
        function onMutedChanged(muted: bool): void {
            if (muted) trigger(0, "volume-mute")
            else       onVolumeChanged(audio.vol)
        }
        // ipc only
        function showVolume(value: int): void { trigger(value, value < 15 ? "volume-low" : "volume") }
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

                    // Icon
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        color: state.icon === "volume-mute" ? cfg.color.base03 : cfg.color.base05
                        font.family: cfg.fontFamily
                        font.pixelSize: cfg.fontSize + 6
                        text: {
                            switch (state.icon) {
                                case "volume-mute": return "\uF026"  // fa-volume-off
                                case "volume-low":  return "\uF027"  // fa-volume-down
                                default:            return "\uF028"  // fa-volume-up
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
