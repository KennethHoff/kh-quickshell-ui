// A quick-toggle tile for the ControlCenter panel.
// Appears as a rounded pill that is highlighted when active.
// Emit tileClicked() from an onTileClicked handler to respond to clicks.
import QtQuick

Rectangle {
    id: root

    property string label:       ""
    property string sublabel:    ""
    property bool   active:      false

    property color  activeColor:         "#89b4fa"
    property color  inactiveColor:       "#313244"
    property color  activeLabelColor:    "#1e1e2e"
    property color  inactiveLabelColor:  "#cdd6f4"
    property color  sublabelColor:       "#6c7086"

    property string fontFamily: "monospace"
    property int    fontSize:   13

    signal tileClicked()

    QtObject {
        id: functionality
        // ui only
        function click(): void { root.tileClicked() }
    }

    implicitWidth:  90
    implicitHeight: 44
    radius: 8
    color: active ? activeColor : inactiveColor

    Column {
        anchors.centerIn: parent
        spacing: 2

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text:           root.label
            color:          root.active ? root.activeLabelColor : root.inactiveLabelColor
            font.family:    root.fontFamily
            font.pixelSize: root.fontSize - 2
            font.bold:      root.active
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text:           root.sublabel
            color:          root.active
                                ? Qt.darker(root.activeLabelColor, 1.5)
                                : root.sublabelColor
            font.family:    root.fontFamily
            font.pixelSize: root.fontSize - 4
            visible:        root.sublabel !== ""
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: functionality.click()
    }
}
