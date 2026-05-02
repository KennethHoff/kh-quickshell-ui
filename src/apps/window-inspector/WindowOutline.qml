// Outline drawn over the picked window. Coordinates from `lastIpcObject`
// are global; we subtract this layer surface's monitor origin to get the
// layer-local position. Hidden when no window is picked or when the
// picked window lives on a different monitor than this layer surface.
import QtQuick

Item {
    id: root

    // ── Inputs ────────────────────────────────────────────────────────────────
    property var   ipc:           null   // hyprctl client record
    // The HyprlandMonitor of the layer surface this overlay sits inside.
    // Used both to position the outline (in layer-local coords) and to
    // decide whether to render at all (the picked window must live here).
    property var   thisMonitor:   null
    property bool  frozen:        false

    property color outlineColor:  "#89b4fa"
    property color frozenColor:   "#f9e2af"

    // The window's monitor id, as reported by hyprctl. Compared against
    // thisMonitor.id so each layer surface only paints when the picked
    // window is actually on its output.
    readonly property int _windowMonitorId: ipc && ipc.monitor !== undefined ? ipc.monitor : -1

    visible: ipc !== null && thisMonitor !== null && ipc.at && ipc.size
          && thisMonitor.id === _windowMonitorId

    Rectangle {
        x:      root.ipc ? root.ipc.at[0]   - (root.thisMonitor ? root.thisMonitor.x : 0) : 0
        y:      root.ipc ? root.ipc.at[1]   - (root.thisMonitor ? root.thisMonitor.y : 0) : 0
        width:  root.ipc ? root.ipc.size[0] : 0
        height: root.ipc ? root.ipc.size[1] : 0
        color: "transparent"
        border.width: 3
        border.color: root.frozen ? root.frozenColor : root.outlineColor
        radius: 2
    }
}
