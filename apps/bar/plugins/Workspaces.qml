// Bar plugin: Hyprland workspace switcher with hover preview.
// Shows all workspaces; highlights the focused one. Click to activate.
// Hover for ~300 ms to show a live thumbnail of the workspace contents.
//
// Each workspace owns its own BarTooltip — hover/delay/dismiss are
// handled by the tooltip primitive, and multiple previews can coexist
// (e.g. via showPreview() IPC pins) because the popup is no longer
// shared across delegates.
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

BarPlugin {
    id: root
    ipcName: "workspaces"
    NixConfig { id: cfg }

    QtObject {
        id: functionality

        // ui+ipc
        function activateWorkspace(ws): void { ws.activate() }
        // ipc only
        function getFocused(): string {
            for (let i = 0; i < Hyprland.workspaces.values.length; i++)
                if (Hyprland.workspaces.values[i].focused)
                    return Hyprland.workspaces.values[i].name
            return ""
        }
        // ipc only
        function list(): string {
            const names = []
            for (let i = 0; i < Hyprland.workspaces.values.length; i++)
                names.push(Hyprland.workspaces.values[i].name)
            return names.join("\n")
        }
        // ipc only
        function switchTo(name: string): void {
            for (let i = 0; i < Hyprland.workspaces.values.length; i++)
                if (Hyprland.workspaces.values[i].name === name)
                    { activateWorkspace(Hyprland.workspaces.values[i]); return }
        }
        // ipc only — pin the matching workspace's BarTooltip.
        function showPreview(name: string): void {
            for (let i = 0; i < _repeater.count; i++) {
                const item = _repeater.itemAt(i)
                if (item && item.ws && item.ws.name === name) {
                    item.tooltip.pin()
                    return
                }
            }
        }
        // ipc only — unpin every BarTooltip.
        function hidePreview(): void {
            for (let i = 0; i < _repeater.count; i++) {
                const item = _repeater.itemAt(i)
                if (item && item.tooltip) item.tooltip.unpin()
            }
        }
    }

    IpcHandler {
        target: ipcPrefix
        function getFocused(): string               { return functionality.getFocused() }
        function list(): string                     { return functionality.list() }
        function switchTo(name: string): void       { functionality.switchTo(name) }
        function showPreview(name: string): void    { functionality.showPreview(name) }
        function hidePreview(): void                { functionality.hidePreview() }
    }

    implicitWidth: row.implicitWidth

    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: 4

        Repeater {
            id: _repeater
            model: Hyprland.workspaces

            delegate: Rectangle {
                id: _delegate

                // Exposed so the plugin-root functionality can find this
                // delegate by workspace name and call tooltip.pin() on it.
                readonly property var ws: modelData
                readonly property alias tooltip: _tip

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
                    onClicked: functionality.activateWorkspace(modelData)
                }

                // Per-delegate hover preview. BarTooltip's HoverHandler
                // tracks the delegate's geometry; opens after 300 ms;
                // dismisses on mouse leave unless pinned via IPC.
                BarTooltip {
                    id: _tip
                    bg: cfg.color.base00           // darker bg for thumbnail contrast
                    padding: 0                      // thumbnail fills to the borders
                    ipcName: "ws" + modelData.name  // addressable as <prefix>.ws<name>

                    // Dimensions: 240 px wide, aspect-matched to the
                    // workspace's monitor. Monitor width/height are physical
                    // pixels; divide by scale to get logical pixels (the
                    // coordinate space used by lastIpcObject).
                    readonly property var mon: Hyprland.monitors.values.find(m => m.activeWorkspace === modelData)
                    readonly property real mon_scale: mon?.scale ?? 1
                    readonly property real mon_w: (mon?.width  ?? 1920) / mon_scale
                    readonly property real mon_h: (mon?.height ?? 1080) / mon_scale
                    readonly property real scale: 240 / mon_w

                    Item {
                        implicitWidth:  240
                        implicitHeight: Math.round(_tip.mon_h * _tip.scale)
                        clip: true

                        // ── Window thumbnails ─────────────────────────
                        Repeater {
                            model: modelData?.toplevels?.values ?? []

                            delegate: Item {
                                readonly property var ipc: modelData.lastIpcObject
                                x: ipc && ipc.at
                                    ? Math.round((ipc.at[0] - (_tip.mon?.x ?? 0)) * _tip.scale)
                                    : 0
                                y: ipc && ipc.at
                                    ? Math.round((ipc.at[1] - (_tip.mon?.y ?? 0)) * _tip.scale)
                                    : 0
                                width:  ipc && ipc.size ? Math.round(ipc.size[0] * _tip.scale) : 0
                                height: ipc && ipc.size ? Math.round(ipc.size[1] * _tip.scale) : 0
                                clip: true

                                ScreencopyView {
                                    anchors.fill: parent
                                    captureSource: modelData.wayland ?? null
                                    live: true
                                }
                            }
                        }

                        // ── Workspace name badge ──────────────────────
                        Text {
                            anchors {
                                right:  parent.right
                                bottom: parent.bottom
                                margins: 4
                            }
                            text:           _delegate.ws.name
                            color:          cfg.color.base05
                            font.family:    cfg.fontFamily
                            font.pixelSize: cfg.fontSize - 3
                            font.bold:      true
                        }
                    }
                }
            }
        }
    }
}
