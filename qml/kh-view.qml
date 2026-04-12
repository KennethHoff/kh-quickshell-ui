// Standalone fullscreen text / image viewer.
//
// Usage (via wrapper): nix run .#kh-view -- <file> [<file2>]
//                      <cmd> | nix run .#kh-view
//
// Direct (Quickshell): KH_VIEW_FILE=/path KH_VIEW_FILE2=/path quickshell -p <config-dir>
//
// Press q or Esc to quit. Tab switches pane in split mode.
// hjkl / Ctrl+D/U to scroll. v/V/Ctrl+V visual select. y copies selection.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "./lib"

ShellRoot {
    id: root

    NixConfig { id: cfg }
    NixBins   { id: bin }

    // ── File 1 state ──────────────────────────────────────────────────────────
    property string _filePath:  ""
    property string _text:      ""
    property bool   _isImage:   false
    property string _imgSrc:    ""
    property bool   _loading:   true
    property var    _lines:     []

    // ── File 2 state ──────────────────────────────────────────────────────────
    property string _filePath2: ""
    property string _text2:     ""
    property bool   _isImage2:  false
    property string _imgSrc2:   ""
    property bool   _loading2:  true
    property var    _lines2:    []

    // ── Split / focus state ───────────────────────────────────────────────────
    property bool _split:      false
    property bool _focusLeft:  true

    Component.onCompleted: { pathProcess.running = true; pathProcess2.running = true }

    // ── File 1: read path ─────────────────────────────────────────────────────
    Process {
        id: pathProcess
        command: [bin.bash, "-c", "printf '%s\\n' \"$KH_VIEW_FILE\""]
        stdout: SplitParser { onRead: (line) => { root._filePath += line } }
        onExited: {
            if (root._filePath === "") { Qt.quit(); return }
            const ext = root._filePath.split(".").pop().toLowerCase()
            root._isImage = ["png","jpg","jpeg","gif","webp","bmp","svg"].includes(ext)
            if (root._isImage) { root._imgSrc = "file://" + root._filePath; root._loading = false }
            else                  readProcess.running = true
        }
    }
    Process {
        id: readProcess
        command: [bin.bash, "-c", "cat -- \"$KH_VIEW_FILE\""]
        stdout: SplitParser { onRead: (line) => { root._lines.push(line) } }
        onExited: { root._text = root._lines.join("\n"); root._lines = []; root._loading = false }
    }

    // ── File 2: read path ─────────────────────────────────────────────────────
    Process {
        id: pathProcess2
        command: [bin.bash, "-c", "printf '%s\\n' \"$KH_VIEW_FILE2\""]
        stdout: SplitParser { onRead: (line) => { root._filePath2 += line } }
        onExited: {
            if (root._filePath2 === "") { root._loading2 = false; return }
            root._split = true
            const ext = root._filePath2.split(".").pop().toLowerCase()
            root._isImage2 = ["png","jpg","jpeg","gif","webp","bmp","svg"].includes(ext)
            if (root._isImage2) { root._imgSrc2 = "file://" + root._filePath2; root._loading2 = false }
            else                   readProcess2.running = true
        }
    }
    Process {
        id: readProcess2
        command: [bin.bash, "-c", "cat -- \"$KH_VIEW_FILE2\""]
        stdout: SplitParser { onRead: (line) => { root._lines2.push(line) } }
        onExited: { root._text2 = root._lines2.join("\n"); root._lines2 = []; root._loading2 = false }
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

            Keys.onPressed: (event) => {
                if (event.key === Qt.Key_Shift   || event.key === Qt.Key_Control ||
                    event.key === Qt.Key_Alt     || event.key === Qt.Key_Meta) return
                if (event.text === "q" || event.key === Qt.Key_Escape) {
                    Qt.quit(); event.accepted = true; return
                }
                if (event.key === Qt.Key_Tab && root._split) {
                    root._focusLeft = !root._focusLeft; event.accepted = true; return
                }
                const active = (root._split && !root._focusLeft) ? viewer2 : viewer
                if (active.handleKey(event)) event.accepted = true
            }

            // Left / single viewer
            TextViewer {
                id: viewer
                x: 0
                width: root._split ? Math.floor(parent.width / 2) : parent.width
                height: parent.height

                text:        root._text
                isImage:     root._isImage
                imageSource: root._imgSrc
                focused:     !root._split || root._focusLeft
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

            // Divider
            Rectangle {
                visible: root._split
                x: Math.floor(parent.width / 2)
                width: 1
                height: parent.height
                color: root._focusLeft ? cfg.color.base0D : cfg.color.base02
            }

            // Right viewer
            TextViewer {
                id: viewer2
                visible: root._split
                x: Math.floor(parent.width / 2) + 1
                width: parent.width - Math.floor(parent.width / 2) - 1
                height: parent.height

                text:        root._text2
                isImage:     root._isImage2
                imageSource: root._imgSrc2
                focused:     root._split && !root._focusLeft
                loading:     root._loading2

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
