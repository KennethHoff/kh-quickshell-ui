// Bar plugin: live clock (HH:mm, updates every second).
import QtQuick

BarWidget {
    NixConfig { id: cfg }

    implicitWidth: label.implicitWidth + 24

    QtObject {
        id: functionality
        // ui only
        function refresh(): void { label.text = Qt.formatTime(new Date(), "HH:mm:ss") }
    }

    Text {
        id: label
        anchors.centerIn: parent
        color: cfg.color.base05
        font.family:    cfg.fontFamily
        font.pixelSize: cfg.fontSize - 1
        Component.onCompleted: functionality.refresh()
    }

    Timer {
        interval: 1000
        running:  true
        repeat:   true
        onTriggered: functionality.refresh()
    }
}
