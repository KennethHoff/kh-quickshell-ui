// Bar plugin: default sink volume with mute toggle.
// Click to toggle mute. Scroll to adjust volume ±5% per notch.
import QtQuick
import Quickshell.Io
import Quickshell.Services.Pipewire

BarPlugin {
    NixConfig { id: cfg }

    // Bind the default sink so its audio properties stay live.
    PwObjectTracker { objects: [Pipewire.defaultAudioSink] }

    // State in a QtObject so its id is globally accessible from nested children.
    QtObject {
        id: state
        readonly property var  sink:  Pipewire.defaultAudioSink
        readonly property bool valid: sink !== null && sink.audio !== null
        readonly property bool muted: valid && sink.audio.muted
        readonly property real vol:   valid ? sink.audio.volume : 0
    }

    QtObject {
        id: functionality

        // ui+ipc
        function apply(v: real): void         { if (state.valid) state.sink.audio.volume = Math.max(0.0, Math.min(1.5, v)) }
        // ui+ipc
        function toggleMute(): void           { if (state.valid) state.sink.audio.muted = !state.sink.audio.muted }
        // ipc only
        function setMuted(m: bool): void      { if (state.valid) state.sink.audio.muted = m }
        // ui+ipc
        function scrollVolume(up: bool): void { apply(state.vol + (up ? 0.05 : -0.05)) }
        // ui only
        function onWheel(angleDelta: real): void { scrollVolume(angleDelta > 0) }
        // ipc only
        function getVolume(): real { return state.valid ? Math.round(state.vol * 100) : 0 }
        // ipc only
        function setVolume(v: int): void { apply(v / 100.0) }
        // ipc only
        function adjustVolume(delta: int): void { apply(state.vol + delta / 100.0) }
    }

    IpcHandler {
        target: ipcPrefix + ".volume"

        function getVolume(): real              { return functionality.getVolume() }
        function setVolume(v: int): void        { functionality.setVolume(v) }
        function adjustVolume(delta: int): void { functionality.adjustVolume(delta) }
        function isMuted(): bool                { return state.muted }
        function setMuted(muted: bool): void    { functionality.setMuted(muted) }
        function toggleMute(): void             { functionality.toggleMute() }
    }

    implicitWidth: label.implicitWidth + 24

    Text {
        id: label
        anchors.centerIn: parent
        color: state.muted ? cfg.color.base03 : cfg.color.base05
        font.family:    cfg.fontFamily
        font.pixelSize: cfg.fontSize - 1
        text: state.muted ? "vol: mute" : "vol: " + Math.round(state.vol * 100) + "%"
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        onClicked: functionality.toggleMute()
        onWheel: wheel => functionality.onWheel(wheel.angleDelta.y)
    }
}
