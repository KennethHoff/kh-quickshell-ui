// Outline drawn over the picked window. Coordinates from `lastIpcObject`
// are global; we subtract the monitor's origin to get the layer-shell-local
// position. Hidden when no window is picked or when the picked window
// lives on a different monitor than this layer surface.
import QtQuick

Item {
    id: root

    // ── Inputs ────────────────────────────────────────────────────────────────
    property var   ipc:           null   // hyprctl client record
    property var   monitorOf:     null   // HyprlandMonitor the window is on
    property bool  frozen:        false

    property color outlineColor:  "#89b4fa"
    property color frozenColor:   "#f9e2af"

    // ── Visible only when we have geometry ────────────────────────────────────
    visible: ipc !== null && monitorOf !== null && ipc.at && ipc.size

    Rectangle {
        x:      root.ipc ? root.ipc.at[0]   - (root.monitorOf ? root.monitorOf.x : 0) : 0
        y:      root.ipc ? root.ipc.at[1]   - (root.monitorOf ? root.monitorOf.y : 0) : 0
        width:  root.ipc ? root.ipc.size[0] : 0
        height: root.ipc ? root.ipc.size[1] : 0
        color: "transparent"
        border.width: 3
        border.color: root.frozen ? root.frozenColor : root.outlineColor
        radius: 2
    }
}
