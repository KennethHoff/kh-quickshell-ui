// Bar plugin: default sink volume with mute toggle.
// Click to toggle mute. Scroll to adjust volume ±5% per notch.
import QtQuick
import Quickshell.Services.Pipewire

BarWidget {
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
        onClicked: if (state.valid) state.sink.audio.muted = !state.sink.audio.muted
        onWheel: wheel => {
            if (!state.valid) return
            const step = wheel.angleDelta.y > 0 ? 0.05 : -0.05
            state.sink.audio.volume = Math.max(0.0, Math.min(1.0, state.sink.audio.volume + step))
        }
    }
}
