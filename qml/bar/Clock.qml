// Bar plugin: live clock (HH:mm, updates every second).
import QtQuick

BarWidget {
    NixConfig { id: cfg }

    implicitWidth: label.implicitWidth + 24

    Text {
        id: label
        anchors.centerIn: parent
        color: cfg.color.base05
        font.family:    cfg.fontFamily
        font.pixelSize: cfg.fontSize - 1

        function refresh() { text = Qt.formatTime(new Date(), "HH:mm") }
        Component.onCompleted: refresh()
    }

    Timer {
        interval: 1000
        running:  true
        repeat:   true
        onTriggered: label.refresh()
    }
}
