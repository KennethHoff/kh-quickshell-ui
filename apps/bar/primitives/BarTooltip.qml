// Generic hover tooltip for bar elements.
//
// Place as a child of any bar item to surface secondary detail on hover:
//
//   BarPlugin {
//       // ... plugin visuals ...
//       BarTooltip {
//           BarText { text: "explains what's wrong" }
//       }
//   }
//
// The tooltip attaches to its direct parent's geometry — hover over any
// pixel of the parent shows it after `delay` ms, mouse leave hides it
// immediately. Child content goes inside a themed rectangle positioned
// just below the bar, centred on the parent and clamped to the screen.
// Set `active: false` to disable without removing the component.
//
// IPC: set `ipcName` and the tooltip is reachable as "<ipcPrefix>.<ipcName>"
// with pin/unpin/togglePin — these keep it visible regardless of hover.
// Hover and pin are independent inputs; visible = (hoverShown OR pinned)
// AND active. (Named `pin`, not `show`, to avoid colliding with the
// `qs ipc show` CLI subcommand.)
import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root

    // Turn the tooltip on/off without removing it from the tree. Useful for
    // error-only tooltips: bind to `hasError` so the tooltip exists but
    // only triggers when there's something worth saying.
    property bool active: true

    // Hover-before-show delay (ms). Matches the 300 ms convention used
    // elsewhere (workspace previews, help overlays).
    property int delay: 300

    // Padding inside the themed rectangle around the content.
    property int padding: 8

    // Optional IPC name. When set, exposes `<ipcPrefix>.<ipcName>` with
    // pin / unpin / togglePin / isPinned / isVisible.
    property string ipcName: ""

    // Scoped IPC prefix — walks the parent chain for the nearest ancestor's
    // ipcPrefix and appends this tooltip's own ipcName segment, mirroring
    // BarPlugin's pattern so nested tooltips and plugins produce consistent
    // dotted targets (e.g. "dev-bar.sonarr.error"). Empty string means the
    // walk failed — IpcHandler below refuses to enable so we never register
    // under a fabricated namespace.
    readonly property string ipcPrefix: {
        var inherited = ""
        let p = parent
        while (p) {
            if (typeof p.ipcPrefix === "string") { inherited = p.ipcPrefix; break }
            p = p.parent
        }
        return ipcName !== "" ? inherited + "." + ipcName : inherited
    }

    NixConfig { id: _cfg }

    property color bg:     _cfg.color.base01
    property color border: _cfg.color.base02

    // Children of BarTooltip render inside the popup.
    default property alias content: _content.data

    // Fill the parent so HoverHandler below tracks the full parent area.
    anchors.fill: parent

    // Walk the parent chain to find barWindow/barHeight. Same pattern as
    // BarPlugin.ipcPrefix — any ancestor that exposes these wins.
    readonly property var _barWindow: {
        let p = parent
        while (p) {
            if (p.barWindow) return p.barWindow
            p = p.parent
        }
        return null
    }
    readonly property int _barHeight: {
        let p = parent
        while (p) {
            if (typeof p.barHeight === "number") return p.barHeight
            p = p.parent
        }
        return 32
    }

    QtObject {
        id: _state
        property bool hoverShown: false
        property bool pinned:     false
    }

    readonly property bool _visible: (_state.hoverShown || _state.pinned) && root.active

    // Public methods — callable from QML as `myTooltip.pin()` etc. IPC
    // handlers and external plugins (e.g. Workspaces.showPreview) both
    // go through these.
    function pin(): void       { functionality.pin() }
    function unpin(): void     { functionality.unpin() }
    function togglePin(): void { functionality.togglePin() }
    function isPinned(): bool  { return _state.pinned }
    function isVisible(): bool { return root._visible }

    QtObject {
        id: functionality

        // ui only
        function onHoveredChanged(): void {
            if (_hover.hovered && root.active) {
                _timer.restart()
            } else {
                _timer.stop()
                _state.hoverShown = false
            }
        }

        // ui only
        function onDelayElapsed(): void {
            if (_hover.hovered && root.active) _state.hoverShown = true
        }

        // ui+ipc
        function pin(): void       { _state.pinned = true }
        // ui+ipc
        function unpin(): void     { _state.pinned = false }
        // ui+ipc
        function togglePin(): void { _state.pinned = !_state.pinned }
    }

    IpcHandler {
        target:  root.ipcPrefix
        enabled: root.ipcName !== "" && root.ipcPrefix !== ""

        function pin(): void       { root.pin() }
        function unpin(): void     { root.unpin() }
        function togglePin(): void { root.togglePin() }
        function isPinned(): bool  { return root.isPinned() }
        function isVisible(): bool { return root.isVisible() }
    }

    HoverHandler {
        id: _hover
        onHoveredChanged: functionality.onHoveredChanged()
    }

    Timer {
        id: _timer
        interval: root.delay
        repeat: false
        onTriggered: functionality.onDelayElapsed()
    }

    PopupWindow {
        id: _popup
        anchor.window: root._barWindow
        anchor.rect.x: root._barWindow
            ? Math.max(4, Math.min(
                Math.round(root.mapToItem(null, root.width / 2, 0).x
                    - _popup.implicitWidth / 2),
                root._barWindow.width - _popup.implicitWidth - 4))
            : 0
        anchor.rect.y: root._barHeight + 4
        visible: root._visible && root._barWindow !== null
        implicitWidth:  _content.implicitWidth  + root.padding * 2
        implicitHeight: _content.implicitHeight + root.padding * 2
        color: "transparent"

        Rectangle {
            anchors.fill: parent
            color:        root.bg
            border.color: root.border
            border.width: 1
            radius: 4
        }

        Item {
            id: _content
            anchors.fill: parent
            anchors.margins: root.padding
            // implicitWidth/Height from children so popup sizes to fit.
            implicitWidth:  childrenRect.width
            implicitHeight: childrenRect.height
        }
    }
}
