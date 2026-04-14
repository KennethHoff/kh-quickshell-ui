// Standalone fullscreen text / image viewer — supports N files side-by-side.
//
// Usage (via wrapper): nix run .#kh-view -- <file> [<file2> ...]
//                      <cmd> | nix run .#kh-view
//
// Direct (Quickshell): KH_VIEW_LIST=/path/to/list quickshell -p <config-dir>
//   where the list file contains one file path per line.
//
// Split mode (default): Tab cycles focus between panes.
// Fullscreen mode (f):  h/l steps through files one at a time.
// Both modes:           hjkl/Ctrl+D/U scroll; v/V/Ctrl+V visual; y yank; q/Esc quit.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "./lib"

ShellRoot {
    id: root

    NixConfig { id: cfg }
    NixBins   { id: bin }

    property var  _paths:       []
    property var  _listLines:   []
    property bool _ready:       false
    property int  _focusedPane: 0
    property bool _fullscreen:  false
    property bool _wrap:        true

    Component.onCompleted: functionality.init()

    // ── Read path list from KH_VIEW_LIST ──────────────────────────────────────
    Process {
        id: listProcess
        command: [bin.bash, "-c", "cat -- \"$KH_VIEW_LIST\""]
        stdout: SplitParser {
            onRead: (line) => functionality.onListRead(line)
        }
        onExited: functionality.onListExited()
    }

    // ── Functionality ─────────────────────────────────────────────────────────
    QtObject {
        id: functionality

        // ui+ipc
        function next(): void             { root._focusedPane = root._wrap ? (root._focusedPane + 1) % root._paths.length : Math.min(root._paths.length - 1, root._focusedPane + 1) }
        // ui+ipc
        function prev(): void             { root._focusedPane = root._wrap ? (root._focusedPane - 1 + root._paths.length) % root._paths.length : Math.max(0, root._focusedPane - 1) }
        // ipc only
        function seek(n: int): void       { root._focusedPane = Math.max(0, Math.min(root._paths.length - 1, n)) }
        // ui only
        function cyclePanes(): void       { root._focusedPane = (root._focusedPane + 1) % root._paths.length }
        // ui+ipc
        function toggleFullscreen(): void { root._fullscreen = !root._fullscreen }
        // ipc only
        function setFullscreen(on: bool): void { root._fullscreen = on }
        // ipc only
        function setWrap(on: bool): void  { root._wrap = on }
        // ui+ipc
        function quit(): void             { Qt.quit() }
        // ipc only
        function key(k: string): void {
            const lk = k.toLowerCase()
            if      (lk === "f")                    toggleFullscreen()
            else if (lk === "q" || lk === "escape") quit()
            else if (lk === "tab" && !root._fullscreen) cyclePanes()
            else if (root._fullscreen && (lk === "h" || lk === "left"))  prev()
            else if (root._fullscreen && (lk === "l" || lk === "right")) next()
            else {
                const pane = paneRepeater.itemAt(root._focusedPane)
                if (pane) pane.handleViewerIpcKey(k)
            }
        }
        // ui only
        function init(): void { listProcess.running = true }
        // ui only
        function onListRead(line: string): void { if (line.trim() !== "") root._listLines.push(line) }
        // ui only
        function onListExited(): void {
            if (root._listLines.length === 0) { Qt.quit(); return }
            root._paths     = root._listLines.slice()
            root._listLines = []
            root._ready     = true
        }
        // ui only
        function onShow(): void { keyHandler.forceActiveFocus() }
        // ui only
        function onYankTextRequested(t: string): void { root._yank(t) }
        // ui only
        function handleKeyEvent(event): void {
            if (event.key === Qt.Key_Shift   || event.key === Qt.Key_Control ||
                event.key === Qt.Key_Alt     || event.key === Qt.Key_Meta) return
            if (event.text === "q" || event.key === Qt.Key_Escape)            { quit();             event.accepted = true; return }
            if (event.text === "f" && root._paths.length > 1)                 { toggleFullscreen(); event.accepted = true; return }
            if (root._fullscreen && (event.key === Qt.Key_H || event.key === Qt.Key_Left))  { prev(); event.accepted = true; return }
            if (root._fullscreen && (event.key === Qt.Key_L || event.key === Qt.Key_Right)) { next(); event.accepted = true; return }
            if (!root._fullscreen && event.key === Qt.Key_Tab && root._paths.length > 1) { cyclePanes(); event.accepted = true; return }
            const pane = paneRepeater.itemAt(root._focusedPane)
            if (pane) event.accepted = pane.handleViewerKey(event)
        }
    }

    IpcHandler {
        target: "viewer"

        readonly property int  currentIndex: root._focusedPane
        readonly property int  count:        root._paths.length
        readonly property bool fullscreen:   root._fullscreen
        readonly property bool wrap:         root._wrap
        readonly property bool hasPrev:      root._wrap || root._focusedPane > 0
        readonly property bool hasNext:      root._wrap || root._focusedPane < root._paths.length - 1

        function quit()                  { functionality.quit() }
        function next()                  { functionality.next() }
        function prev()                  { functionality.prev() }
        function seek(n: int)            { functionality.seek(n) }
        function setFullscreen(on: bool) { functionality.setFullscreen(on) }
        function setWrap(on: bool)       { functionality.setWrap(on) }
        function key(k: string)          { functionality.key(k) }
    }

    // ── Yank ──────────────────────────────────────────────────────────────────
    Process { id: yankProcess }
    function _yank(text) {
        yankProcess.command = [bin.bash, "-c", "printf '%s' \"$1\" | " + bin.wlCopy, "--", text]
        yankProcess.running = true
    }

    // ── Window ────────────────────────────────────────────────────────────────
    WlrLayershell {
        id: win
        visible: true
        color: cfg.color.base00
        layer: WlrLayer.Overlay
        keyboardFocus: WlrKeyboardFocus.Exclusive
        exclusionMode: ExclusionMode.Ignore
        namespace: "kh-view"
        anchors { top: true; bottom: true; left: true; right: true }

        Item {
            id: keyHandler
            anchors.fill: parent
            focus: true
            Component.onCompleted: functionality.onShow()

            readonly property int _paneWidth: root._paths.length > 0
                ? Math.floor(width / root._paths.length) : width

            Keys.onPressed: (event) => functionality.handleKeyEvent(event)

            Repeater {
                id: paneRepeater
                model: root._ready ? root._paths : []

                delegate: Item {
                    id: pane
                    required property string modelData  // file path
                    required property int    index

                    visible: !root._fullscreen || pane.index === root._focusedPane
                    x:      root._fullscreen ? 0 : pane.index * keyHandler._paneWidth
                    width:  root._fullscreen ? keyHandler.width
                            : pane.index < root._paths.length - 1
                              ? keyHandler._paneWidth
                              : keyHandler.width - pane.index * keyHandler._paneWidth
                    height: keyHandler.height

                    property string _text:    ""
                    property bool   _isImage: false
                    property string _imgSrc:  ""
                    property bool   _loading: true
                    property var    _lines:   []

                    function handleViewerKey(event)      { return paneViewer.handleKey(event) }
                    function handleViewerIpcKey(k: string) { return paneViewer.handleIpcKey(k) }

                    QtObject {
                        id: paneFunctionality
                        // ui only
                        function init(): void {
                            const ext = pane.modelData.split(".").pop().toLowerCase()
                            pane._isImage = ["png","jpg","jpeg","gif","webp","bmp","svg"].includes(ext)
                            if (pane._isImage) { pane._imgSrc = "file://" + pane.modelData; pane._loading = false }
                            else               readProc.running = true
                        }
                        // ui only
                        function onReadLine(line: string): void { pane._lines.push(line) }
                        // ui only
                        function onReadExited(): void {
                            pane._text    = pane._lines.join("\n")
                            pane._lines   = []
                            pane._loading = false
                        }
                    }

                    Component.onCompleted: paneFunctionality.init()

                    Process {
                        id: readProc
                        command: [bin.bash, "-c", "cat -- \"$1\"", "--", pane.modelData]
                        stdout: SplitParser {
                            onRead: (line) => paneFunctionality.onReadLine(line)
                        }
                        onExited: paneFunctionality.onReadExited()
                    }

                    // Divider on the left edge (split mode only, not first pane)
                    Rectangle {
                        visible: !root._fullscreen && pane.index > 0
                        x: 0; width: 1; height: parent.height
                        color: root._focusedPane === pane.index ? cfg.color.base0D : cfg.color.base02
                    }

                    TextViewer {
                        id: paneViewer
                        anchors.fill: parent

                        text:        pane._text
                        isImage:     pane._isImage
                        imageSource: pane._imgSrc
                        focused:     root._focusedPane === pane.index
                        loading:     pane._loading

                        textColor:          cfg.color.base05
                        selectionColor:     cfg.color.base0D
                        selectionTextColor: cfg.color.base00
                        cursorColor:        cfg.color.base07
                        dimColor:           cfg.color.base03
                        fontFamily:         cfg.fontFamily
                        fontSize:           cfg.fontSize

                        onYankTextRequested: (t) => functionality.onYankTextRequested(t)
                    }
                }
            }

            // Fullscreen mode dot indicators
            Row {
                visible: root._fullscreen && root._paths.length > 1
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottomMargin: 16
                spacing: 8

                Repeater {
                    model: root._ready ? root._paths.length : 0
                    delegate: Rectangle {
                        required property int index
                        width: 8; height: 8; radius: 4
                        color: index === root._focusedPane ? cfg.color.base05 : cfg.color.base03
                    }
                }
            }
        }
    }
}
