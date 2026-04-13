// Bar plugin: Hyprland workspace switcher with hover preview.
// Shows all workspaces; highlights the focused one. Click to activate.
// Hover for ~300 ms to show a live thumbnail of the workspace contents.
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

BarWidget {
    NixConfig { id: cfg }

    // Hover-preview state — one shared popup for all workspace buttons.
    QtObject {
        id: state
        property var  preview: null  // HyprlandWorkspace currently shown
        property var  pending: null  // workspace queued during hover delay
        property real btnX:   0      // button x for popup x-centering
    }

    // 300 ms hover delay before the preview appears.
    Timer {
        id: timer
        interval: 300
        repeat: false
        onTriggered: state.preview = state.pending
    }

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
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: modelData.activate()
                    onEntered: {
                        state.pending = modelData
                        // parent is the delegate Rectangle; map to bar-window coords.
                        state.btnX = parent.mapToItem(null, 0, 0).x
                        timer.restart()
                    }
                    onExited: {
                        timer.stop()
                        state.pending = null
                        state.preview = null
                    }
                }
            }
        }
    }

    // ── Workspace preview popup ────────────────────────────────────────────
    PopupWindow {
        id: panel
        anchor.window: layout.barWindow
        anchor.rect.x: layout.barWindow
            ? Math.max(0, Math.min(
                Math.round(state.btnX + 14 - panel.width / 2),
                layout.barWindow.width - panel.width))
            : 0
        anchor.rect.y: layout.barHeight + 4

        // Dimensions: 240 px wide, aspect-matched to the workspace's monitor.
        readonly property real mon_w: state.preview?.monitor?.width  ?? 1920
        readonly property real mon_h: state.preview?.monitor?.height ?? 1080
        readonly property real scale: 240 / mon_w

        width:  240
        height: Math.round(mon_h * scale)
        color:  "transparent"

        visible: state.preview !== null && layout.barWindow !== null

        Rectangle {
            anchors.fill: parent
            color:        cfg.color.base00
            border.color: cfg.color.base02
            border.width: 1
            radius: 4
            clip: true

            // ── Window thumbnails ─────────────────────────────────────────
            Repeater {
                model: state.preview?.toplevels?.values ?? []

                delegate: Item {
                    readonly property var ipc: modelData.lastIpcObject
                    x: ipc && ipc.at
                        ? Math.round((ipc.at[0] - (state.preview?.monitor?.x ?? 0)) * panel.scale)
                        : 0
                    y: ipc && ipc.at
                        ? Math.round((ipc.at[1] - (state.preview?.monitor?.y ?? 0)) * panel.scale)
                        : 0
                    width:  ipc && ipc.size ? Math.round(ipc.size[0] * panel.scale) : 0
                    height: ipc && ipc.size ? Math.round(ipc.size[1] * panel.scale) : 0
                    clip: true

                    ScreencopyView {
                        anchors.fill: parent
                        captureSource: modelData.wayland ?? null
                        live: false
                        Component.onCompleted: captureFrame()
                    }
                }
            }

            // ── Workspace name badge ───────────────────────────────────────
            Text {
                anchors {
                    right:  parent.right
                    bottom: parent.bottom
                    margins: 4
                }
                text:           state.preview ? state.preview.name : ""
                color:          cfg.color.base05
                font.family:    cfg.fontFamily
                font.pixelSize: cfg.fontSize - 3
                font.bold:      true
            }
        }
    }
}
