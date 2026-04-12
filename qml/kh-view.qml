// Standalone fullscreen text / image viewer.
//
// Usage (via wrapper): nix run .#kh-view -- <file>
//                      <cmd> | nix run .#kh-view
//
// Direct (Quickshell): KH_VIEW_FILE=/path/to/file quickshell -p <config-dir>
//
// Press q or Esc to quit. hjkl / Ctrl+D/U to scroll. v/V/Ctrl+V visual select.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "./lib"

ShellRoot {
    id: root

    NixConfig { id: cfg }
    NixBins   { id: bin }

    property string _filePath: ""
    property string _text:     ""
    property bool   _isImage:  false
    property string _imgSrc:   ""
    property bool   _loading:  true
    property var    _lines:    []

    Component.onCompleted: pathProcess.running = true

    // ── Read file path from env ───────────────────────────────────────────────
    Process {
        id: pathProcess
        command: [bin.bash, "-c", "printf '%s\\n' \"$KH_VIEW_FILE\""]
        stdout: SplitParser {
            onRead: (line) => { root._filePath += line }
        }
        onExited: {
            if (root._filePath === "") { Qt.quit(); return }
            const ext = root._filePath.split(".").pop().toLowerCase()
            root._isImage = ["png","jpg","jpeg","gif","webp","bmp","svg"].includes(ext)
            if (root._isImage) {
                root._imgSrc  = "file://" + root._filePath
                root._loading = false
            } else {
                readProcess.running = true
            }
        }
    }

    // ── Read text content ─────────────────────────────────────────────────────
    Process {
        id: readProcess
        command: [bin.bash, "-c", "cat -- \"$KH_VIEW_FILE\""]
        stdout: SplitParser {
            onRead: (line) => { root._lines.push(line) }
        }
        onExited: {
            root._text    = root._lines.join("\n")
            root._lines   = []
            root._loading = false
        }
    }

    // ── Yank selection to clipboard ───────────────────────────────────────────
    Process { id: yankProcess }
    function _yank(text) {
        yankProcess.command = [
            bin.bash, "-c",
            "printf '%s' \"$1\" | " + bin.wlCopy,
            "--", text
        ]
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

            Keys.onPressed: (event) => {
                if (event.key === Qt.Key_Shift   || event.key === Qt.Key_Control ||
                    event.key === Qt.Key_Alt     || event.key === Qt.Key_Meta) return
                if (event.text === "q" || event.key === Qt.Key_Escape) {
                    Qt.quit(); event.accepted = true; return
                }
                if (viewer.handleKey(event)) event.accepted = true
            }

            TextViewer {
                id: viewer
                anchors.fill: parent

                text:        root._text
                isImage:     root._isImage
                imageSource: root._imgSrc
                focused:     true
                loading:     root._loading

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
}
