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
    property bool _fullscreen:    false

    Component.onCompleted: listProcess.running = true

    // ── Read path list from KH_VIEW_LIST ──────────────────────────────────────
    Process {
        id: listProcess
        command: [bin.bash, "-c", "cat -- \"$KH_VIEW_LIST\""]
        stdout: SplitParser {
            onRead: (line) => { if (line.trim() !== "") root._listLines.push(line) }
        }
        onExited: {
            if (root._listLines.length === 0) { Qt.quit(); return }
            root._paths     = root._listLines.slice()
            root._listLines = []
            root._ready     = true
        }
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
            Component.onCompleted: forceActiveFocus()

            readonly property int _paneWidth: root._paths.length > 0
                ? Math.floor(width / root._paths.length) : width

            Keys.onPressed: (event) => {
                if (event.key === Qt.Key_Shift   || event.key === Qt.Key_Control ||
                    event.key === Qt.Key_Alt     || event.key === Qt.Key_Meta) return
                if (event.text === "q" || event.key === Qt.Key_Escape) {
                    Qt.quit(); event.accepted = true; return
                }

                // Toggle fullscreen mode
                if (event.text === "f" && root._paths.length > 1) {
                    root._fullscreen = !root._fullscreen; event.accepted = true; return
                }

                if (root._fullscreen) {
                    // h/l navigate between files
                    if (event.key === Qt.Key_H || event.key === Qt.Key_Left) {
                        root._focusedPane = Math.max(0, root._focusedPane - 1)
                        event.accepted = true; return
                    }
                    if (event.key === Qt.Key_L || event.key === Qt.Key_Right) {
                        root._focusedPane = Math.min(root._paths.length - 1, root._focusedPane + 1)
                        event.accepted = true; return
                    }
                } else {
                    // Tab cycles focus in split mode
                    if (event.key === Qt.Key_Tab && root._paths.length > 1) {
                        root._focusedPane = (root._focusedPane + 1) % root._paths.length
                        event.accepted = true; return
                    }
                }

                const pane = paneRepeater.itemAt(root._focusedPane)
                if (pane && pane.handleViewerKey(event)) event.accepted = true
            }

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

                    function handleViewerKey(event) { return paneViewer.handleKey(event) }

                    Component.onCompleted: {
                        const ext = modelData.split(".").pop().toLowerCase()
                        _isImage = ["png","jpg","jpeg","gif","webp","bmp","svg"].includes(ext)
                        if (_isImage) { _imgSrc = "file://" + modelData; _loading = false }
                        else           readProc.running = true
                    }

                    Process {
                        id: readProc
                        command: [bin.bash, "-c", "cat -- \"$1\"", "--", pane.modelData]
                        stdout: SplitParser {
                            onRead: (line) => { pane._lines.push(line) }
                        }
                        onExited: {
                            pane._text    = pane._lines.join("\n")
                            pane._lines   = []
                            pane._loading = false
                        }
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

                        onYankTextRequested: (t) => root._yank(t)
                    }
                }
            }

            // Carousel position indicator: "2 / 5"
            Text {
                visible: root._fullscreen && root._paths.length > 1
                anchors.bottom: parent.bottom
                anchors.right: parent.right
                anchors.margins: 12
                text: (root._focusedPane + 1) + " / " + root._paths.length
                color: cfg.color.base03
                font.family: cfg.fontFamily
                font.pixelSize: cfg.fontSize - 2
            }
        }
    }
}
