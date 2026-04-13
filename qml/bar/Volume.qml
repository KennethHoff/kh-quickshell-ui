// Bar plugin: default sink volume with mute toggle.
// Click to toggle mute. Scroll to adjust volume ±5% per notch.
import QtQuick
import Quickshell.Services.Pipewire

BarWidget {
    NixConfig { id: cfg }

    // Bind the default sink so its audio properties stay live.
    PwObjectTracker { objects: [Pipewire.defaultAudioSink] }

    readonly property PwNode sink:  Pipewire.defaultAudioSink
    readonly property bool   valid: sink !== null && sink.audio !== null
    readonly property bool   muted: valid && sink.audio.muted
    readonly property real   vol:   valid ? sink.audio.volume : 0

    implicitWidth: label.implicitWidth + 24

    Text {
        id: label
        anchors.centerIn: parent
        color: muted ? cfg.color.base03 : cfg.color.base05
        font.family:    cfg.fontFamily
        font.pixelSize: cfg.fontSize - 1
        text: muted ? "vol: mute" : "vol: " + Math.round(vol * 100) + "%"
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        onClicked: if (valid) sink.audio.muted = !sink.audio.muted
        onWheel: wheel => {
            if (!valid) return
            const step = wheel.angleDelta.y > 0 ? 0.05 : -0.05
            sink.audio.volume = Math.max(0.0, Math.min(1.0, sink.audio.volume + step))
        }
    }
}
