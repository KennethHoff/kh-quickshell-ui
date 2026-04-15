// Bar plugin: system tray icons (StatusNotifierItem protocol).
// Left click activates the item; right click shows its context menu.
// Hidden entirely when no tray items are present.
import QtQuick
import Quickshell.Io
import Quickshell.Services.SystemTray

BarPlugin {
    NixConfig { id: cfg }

    IpcHandler {
        target: ipcPrefix + ".tray"

        function list(): string {
            const titles = []
            for (let i = 0; i < SystemTray.items.values.length; i++)
                titles.push(SystemTray.items.values[i].title)
            return titles.join("\n")
        }
        function activate(title: string): void {
            for (let i = 0; i < SystemTray.items.values.length; i++) {
                const item = SystemTray.items.values[i]
                if (item.title === title && !item.onlyMenu) { item.activate(); return }
            }
        }
        function showMenu(title: string): void {
            for (let i = 0; i < SystemTray.items.values.length; i++) {
                const item = SystemTray.items.values[i]
                if (item.title === title && item.hasMenu) { item.display(barWindow, 0, barHeight); return }
            }
        }
    }

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
                id: trayItem
                implicitWidth:  20
                implicitHeight: 20
                anchors.verticalCenter: parent.verticalCenter

                QtObject {
                    id: functionality

                    // ui only
                    function activate(): void           { modelData.activate() }
                    // ui only
                    function showMenu(mouseArea): void  { const pos = mouseArea.mapToItem(null, 0, mouseArea.height); modelData.display(barWindow, pos.x, pos.y) }
                    // ui only
                    function click(mouse, mouseArea): void {
                        if (mouse.button === Qt.LeftButton && !modelData.onlyMenu) activate()
                        else if (modelData.hasMenu) showMenu(mouseArea)
                    }
                }

                Image {
                    anchors.centerIn: parent
                    width: 16; height: 16
                    source: modelData.icon
                    smooth: true
                    mipmap: true
                }

                MouseArea {
                    id: trayMouseArea
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: mouse => functionality.click(mouse, trayMouseArea)
                }
            }
        }
    }
}
