// Bar plugin: Hyprland workspace switcher.
// Shows all workspaces; highlights the focused one. Click to activate.
import QtQuick
import Quickshell.Hyprland

BarWidget {
    NixConfig { id: cfg }

    implicitWidth: row.implicitWidth

    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: 4

        Repeater {
            model: Hyprland.workspaces

            delegate: Rectangle {
                width: 28
                height: 22
                radius: 4
                color: modelData.focused ? cfg.color.base0D
                     : modelData.active  ? cfg.color.base02
                     :                     "transparent"
                border.color: modelData.focused ? cfg.color.base0D
                            : modelData.active  ? cfg.color.base04
                            :                     cfg.color.base03
                border.width: 1

                Text {
                    anchors.centerIn: parent
                    text: modelData.name
                    color: modelData.focused ? cfg.color.base00
                         :                     cfg.color.base05
                    font.family:    cfg.fontFamily
                    font.pixelSize: cfg.fontSize - 2
                    font.bold:      modelData.focused
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: modelData.activate()
                }
            }
        }
    }
}
