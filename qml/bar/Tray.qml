// Bar plugin: system tray icons (StatusNotifierItem protocol).
// Left click activates the item; right click shows its context menu.
// Hidden entirely when no tray items are present.
import QtQuick
import Quickshell.Services.SystemTray

BarWidget {
    NixConfig { id: cfg }

    implicitWidth: SystemTray.items.values.length > 0
        ? row.implicitWidth + 8 : 0
    visible: SystemTray.items.values.length > 0

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 4

        Repeater {
            model: SystemTray.items

            delegate: Item {
                implicitWidth:  20
                implicitHeight: 20
                anchors.verticalCenter: parent.verticalCenter

                Image {
                    anchors.centerIn: parent
                    width: 16; height: 16
                    source: modelData.icon
                    smooth: true
                    mipmap: true
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: mouse => {
                        if (mouse.button === Qt.LeftButton && !modelData.onlyMenu) {
                            modelData.activate()
                        } else if (modelData.hasMenu) {
                            const pos = mapToItem(null, 0, height)
                            modelData.display(layout.barWindow, pos.x, pos.y)
                        }
                    }
                }
            }
        }
    }
}
