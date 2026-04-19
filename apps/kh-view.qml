// Standalone fullscreen text / image viewer — supports N files side-by-side.
//
// Usage (via wrapper): nix run .#kh-view -- <file-or-dir> [<file-or-dir2> ...]
//                      <cmd> | nix run .#kh-view
//
// Directory args are expanded by the wrapper to their image files.
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

    property var  _panes:       []
    property var  _listItems:   []
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
        function next(): void             { root._focusedPane = root._wrap ? (root._focusedPane + 1) % root._panes.length : Math.min(root._panes.length - 1, root._focusedPane + 1) }
        // ui+ipc
        function prev(): void             { root._focusedPane = root._wrap ? (root._focusedPane - 1 + root._panes.length) % root._panes.length : Math.max(0, root._focusedPane - 1) }
        // ipc only
        function seek(n: int): void       { root._focusedPane = Math.max(0, Math.min(root._panes.length - 1, n)) }
        // ui only
        function cyclePanes(): void       { root._focusedPane = (root._focusedPane + 1) % root._panes.length }
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
        function onListRead(line: string): void { 
            if (line.trim() === "") return
            const parts = line.split("\t")
            root._listItems.push({ path: parts[0] ?? "", label: parts[1] ?? "", desc: parts[2] ?? "" })
        }
        // ui only
        function onListExited(): void {
            if (root._listItems.length === 0) { Qt.quit(); return }
            root._panes     = root._listItems.slice()
            root._listItems = []
            root._ready     = true
        }
        // ui only
        function onShow(): void { keyHandler.forceActiveFocus() }
        // ui only
        function onYankTextRequested(t: string): void { impl.yank(t) }
        // ui only
        function handleKeyEvent(event): void {
            if (event.key === Qt.Key_Shift   || event.key === Qt.Key_Control ||
                event.key === Qt.Key_Alt     || event.key === Qt.Key_Meta) return
            if (event.text === "q" || event.key === Qt.Key_Escape)            { quit();             event.accepted = true; return }
            if (event.text === "f" && root._panes.length > 1)                 { toggleFullscreen(); event.accepted = true; return }
            if (root._fullscreen && (event.key === Qt.Key_H || event.key === Qt.Key_Left))  { prev(); event.accepted = true; return }
            if (root._fullscreen && (event.key === Qt.Key_L || event.key === Qt.Key_Right)) { next(); event.accepted = true; return }
            if (!root._fullscreen && event.key === Qt.Key_Tab && root._panes.length > 1) { cyclePanes(); event.accepted = true; return }
            const pane = paneRepeater.itemAt(root._focusedPane)
            if (pane) event.accepted = pane.handleViewerKey(event)
        }
    }

    IpcHandler {
        target: "view"

        readonly property int  currentIndex: root._focusedPane
        readonly property int  count:        root._panes.length
        readonly property bool fullscreen:   root._fullscreen
        readonly property bool wrap:         root._wrap
        readonly property bool hasPrev:      root._wrap || root._focusedPane > 0
        readonly property bool hasNext:      root._wrap || root._focusedPane < root._panes.length - 1

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

    QtObject {
        id: impl
        function yank(text: string): void {
            yankProcess.command = [bin.bash, "-c", "printf '%s' \"$1\" | " + bin.wlCopy, "--", text]
            yankProcess.running = true
        }
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

            readonly property int _paneWidth: root._panes.length > 0
                ? Math.floor(width / root._panes.length) : width

            Keys.onPressed: (event) => functionality.handleKeyEvent(event)

            Repeater {
                id: paneRepeater
                model: root._ready ? root._panes : []

                delegate: Item {
                    id: pane
                    required property var modelData  // { path, label, desc }
                    required property int    index

                    visible: !root._fullscreen || pane.index === root._focusedPane
                    x:      root._fullscreen ? 0 : pane.index * keyHandler._paneWidth
                    width:  root._fullscreen ? keyHandler.width
                            : pane.index < root._panes.length - 1
                              ? keyHandler._paneWidth
                              : keyHandler.width - pane.index * keyHandler._paneWidth
                    height: keyHandler.height

                    property string _text:    ""
                    property bool   _isImage: false
                    property string _imgSrc:  ""
                    property bool   _loading: true
                    property var    _lines:   []
                    readonly property int  _headerH:  pane.modelData.label ? 44 : 0
                    readonly property bool _hasDots:  root._fullscreen && root._panes.length > 1
                    readonly property int  _dotsGap:  pane._hasDots ? 40 : 0

                    function handleViewerKey(event)      { return paneViewer.handleKey(event) }
                    function handleViewerIpcKey(k: string) { return paneViewer.handleIpcKey(k) }

                    QtObject {
                        id: paneFunctionality
                        // ui only
                        function init(): void {
                            const ext = pane.modelData.path.split(".").pop().toLowerCase()
                            pane._isImage = ["png","jpg","jpeg","gif","webp","bmp","svg"].includes(ext)
                            if (pane._isImage) { pane._imgSrc = "file://" + pane.modelData.path; pane._loading = false }
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
                        command: [bin.bash, "-c", "cat -- \"$1\"", "--", pane.modelData.path]
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

                    // Pane label — centered at the bottom (above dots in fullscreen with multiple panes)
                    Item {
                        id: paneHeader
                        visible: pane.modelData.label !== ""
                        anchors { left: parent.left; right: parent.right }
                        y: parent.height - pane._headerH - pane._dotsGap
                        height: pane._headerH

                        Rectangle {
                            anchors.centerIn: parent
                            width:  labelRow.width + 32
                            height: labelRow.height + 14
                            radius: 8
                            color: cfg.color.base01
                            border.width: 1
                            border.color: cfg.color.base02

                            Row {
                                id: labelRow
                                anchors.centerIn: parent
                                spacing: 14

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: pane.modelData.label
                                    color: cfg.color.base07
                                    font.family: cfg.fontFamily
                                    font.pixelSize: cfg.fontSize + 6
                                    font.bold: true
                                }

                                Text {
                                    visible: pane.modelData.desc !== ""
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "·"
                                    color: cfg.color.base04
                                    font.family: cfg.fontFamily
                                    font.pixelSize: cfg.fontSize + 6
                                }

                                Text {
                                    visible: pane.modelData.desc !== ""
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: pane.modelData.desc
                                    color: cfg.color.base05
                                    font.family: cfg.fontFamily
                                    font.pixelSize: cfg.fontSize + 2
                                }
                            }
                        }
                    }

                    TextViewer {
                        id: paneViewer
                        anchors {
                            top: parent.top
                            left: parent.left; right: parent.right; bottom: parent.bottom
                            bottomMargin: pane._headerH + pane._dotsGap
                        }

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
                visible: root._fullscreen && root._panes.length > 1
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottomMargin: 16
                spacing: 8

                Repeater {
                    model: root._ready ? root._panes.length : 0
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
