// Bar plugin: Hyprland workspace switcher with hover preview.
// Shows all workspaces; highlights the focused one. Click to activate.
// Hover for ~300 ms to show a live thumbnail of the workspace contents.
//
// Each workspace owns its own BarTooltip, parked in a sibling overlay
// rather than inside the button. That lets the plugin move the tooltip
// anchor into a fan-out slot when multiple previews are pinned via IPC
// (showPreview), so pinned previews coexist side-by-side instead of
// stacking at the clamped left margin. When unpinned, the anchor snaps
// back over the button so hover-to-preview lands above it as before.
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

BarPlugin {
    id: root
    ipcName: "workspaces"
    NixConfig { id: cfg }

    // Per-delegate geometry used by both the visible Row and the tooltip
    // overlay. Kept here (not inline) so the overlay's default position
    // tracks the button without duplicating the magic numbers.
    readonly property int _btnW: 28
    readonly property int _btnH: 22
    readonly property int _btnSpacing: 4
    readonly property int _btnStep: _btnW + _btnSpacing

    // Popup geometry for the fan-out layout. Matches the inner Item's
    // implicitWidth below (240). Gap is small — we just need the popups
    // not to touch.
    readonly property int _popupW: 240
    readonly property int _fanGap: 4
    readonly property int _fanStep: _popupW + _fanGap

    QtObject {
        id: functionality

        // Names of currently-pinned workspaces, in pin order. Drives each
        // overlay anchor's fan-out slot via indexOf(name).
        property var pinOrder: []

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
        // ipc only — append the workspace to pinOrder (assigning its
        // fan-out slot) and pin its tooltip. No-op if already pinned.
        function showPreview(name: string): void {
            if (pinOrder.indexOf(name) !== -1) return
            for (let i = 0; i < _tipRepeater.count; i++) {
                const item = _tipRepeater.itemAt(i)
                if (item && item.ws && item.ws.name === name) {
                    pinOrder = pinOrder.concat([name])
                    item.tooltip.pin()
                    return
                }
            }
        }
        // ipc only — unpin every tooltip and clear the fan-out order.
        function hidePreview(): void {
            for (let i = 0; i < _tipRepeater.count; i++) {
                const item = _tipRepeater.itemAt(i)
                if (item && item.tooltip) item.tooltip.unpin()
            }
            pinOrder = []
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
        spacing: root._btnSpacing

        Repeater {
            id: _repeater
            model: Hyprland.workspaces

            delegate: Rectangle {
                id: _delegate

                readonly property var ws: modelData

                width:  root._btnW
                height: root._btnH
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
            }
        }
    }

    // Tooltip overlay — one anchor Item per workspace, sibling to Row
    // rather than a child of the delegate. The anchor Item's geometry
    // drives BarTooltip's centered-above-parent popup: sizing the anchor
    // to the popup width and placing it at the desired x makes the
    // popup land exactly there. When not pinned the anchor tracks the
    // button so hover shows a centered popup above it; when pinned the
    // anchor widens to popupW and slots into the next fan-out position.
    Repeater {
        id: _tipRepeater
        model: Hyprland.workspaces

        delegate: Item {
            id: _anchor

            readonly property var ws: modelData
            readonly property alias tooltip: _tip
            readonly property int pinIdx: functionality.pinOrder.indexOf(modelData.name)
            readonly property bool fanned: pinIdx >= 0

            width:  fanned ? root._popupW : root._btnW
            height: root._btnH
            x: fanned ? (pinIdx * root._fanStep)
                      : (index * root._btnStep)
            y: (parent.height - height) / 2

            BarTooltip {
                id: _tip
                bg: cfg.color.base00           // darker bg for thumbnail contrast
                padding: 0                      // thumbnail fills to the borders
                ipcName: "ws" + modelData.name  // addressable as <prefix>.ws<name>

                // Dimensions: 240 px wide, aspect-matched to the
                // workspace's monitor. Monitor width/height are physical
                // pixels; divide by scale to get logical pixels (the
                // coordinate space used by lastIpcObject).
                // Use the workspace's assigned monitor rather than
                // finding an active mapping: a background workspace
                // (one whose monitor is currently showing a different
                // workspace) still has a home output, and we need its
                // geometry for correct thumbnail placement even though
                // the toplevels aren't being actively rendered.
                readonly property var mon: modelData.monitor
                readonly property real mon_scale: mon?.scale ?? 1
                readonly property real mon_w: (mon?.width  ?? 1920) / mon_scale
                readonly property real mon_h: (mon?.height ?? 1080) / mon_scale
                readonly property real scale: root._popupW / mon_w

                Item {
                    implicitWidth:  root._popupW
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
                        text:           _anchor.ws.name
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
