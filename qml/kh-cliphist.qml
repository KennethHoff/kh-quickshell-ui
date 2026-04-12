// Clipboard history viewer — orchestrator.
//
// Daemon: quickshell -p <config-dir>
// Toggle: quickshell ipc -c kh-cliphist call viewer toggle
//
// This file owns: window, IPC, global paste/yank, focus routing, fullscreen
// overlay, and HelpOverlay. All list and preview logic lives in ClipList and
// ClipPreview respectively. TextViewer and HelpOverlay are reusable lib components.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "./lib"

ShellRoot {
    id: root

    NixConfig { id: cfg }
    NixBins   { id: bin }

    property bool showing:           false
    property bool detailFocused:     false
    property bool fullscreenShowing: false

    // ── Paste / yank ─────────────────────────────────────────────────────────
    function pasteEntry(rawLine) {
        pasteProcess.command = [
            bin.bash, "-c",
            "printf '%s\\n' \"$1\" | " + bin.cliphist + " decode | " + bin.wlCopy,
            "--", rawLine
        ]
        pasteProcess.running = true
        closeTimer.restart()
    }

    function yankText(text) {
        yankTextProcess.command = [
            bin.bash, "-c",
            "printf '%s' \"$1\" | " + bin.wlCopy, "--", text
        ]
        yankTextProcess.running = true
        closeTimer.restart()
    }

    Process { id: pasteProcess }
    Process { id: yankTextProcess }
    Timer   { id: closeTimer; interval: 200; onTriggered: root.showing = false }

    // ── IPC ───────────────────────────────────────────────────────────────────
    IpcHandler {
        target: "viewer"
        readonly property bool   showing: root.showing
        readonly property string mode:    list.mode

        function toggle()           { root.showing = !root.showing }
        function setMode(m: string) {
            if (m === "insert") { list.enterInsertMode() }
            else { list.enterNormalMode(); normalModeHandler.forceActiveFocus() }
        }
        function setView(v: string) {
            if (v === "help")            helpOverlay.open()
            else if (v === "list")       helpOverlay.close()
            else if (v === "fullscreen") { root.fullscreenShowing = true; fsViewer.reset() }
        }
        function nav(dir: string) { list.nav(dir) }
        function key(k: string) {
            const lk = k.toLowerCase()
            if (lk === "?") {
                helpOverlay.showing ? helpOverlay.close() : helpOverlay.open()
            } else if (lk === "/" && helpOverlay.showing) {
                helpOverlay._filtering = true; helpOverlay._filterText = ""
            } else if (lk === "escape" || lk === "esc") {
                if      (helpOverlay.showing)     helpOverlay.close()
                else if (root.fullscreenShowing)  { root.fullscreenShowing = false; fsViewer.reset() }
                else if (root.detailFocused)      { root.detailFocused = false; normalModeHandler.forceActiveFocus() }
                else                              list.handleIpcKey(k)
            } else if (lk === "enter" || lk === "return") {
                if (root.detailFocused && !root.fullscreenShowing)
                    { root.fullscreenShowing = true; fsViewer.reset() }
            } else if (lk === "tab") {
                if (!root.detailFocused && !root.fullscreenShowing)
                    { root.detailFocused = true }
                else if (root.detailFocused)
                    { root.detailFocused = false; normalModeHandler.forceActiveFocus() }
            } else if (lk === "y") {
                if (list._confirmingDelete) { list.handleIpcKey(k) }
                else if (list.selectedEntry !== "")
                    { list.flash(list.selectedIndex); pasteEntry(list.selectedEntry) }
            } else if (lk === "v") {
                if (root.fullscreenShowing || root.detailFocused) preview.handleIpcKey(k)
                else list.handleIpcKey(k)
            } else {
                list.handleIpcKey(k)
            }
        }
        function type(text: string) {
            if (helpOverlay.showing)
                { helpOverlay._filtering = true; helpOverlay._filterText += text }
            else
                list.typeText(text)
        }
    }

    // ── Window ────────────────────────────────────────────────────────────────
    WlrLayershell {
        id: win
        visible: root.showing
        color: "transparent"
        layer: WlrLayer.Overlay
        keyboardFocus: WlrKeyboardFocus.Exclusive
        exclusionMode: ExclusionMode.Ignore
        namespace: "kh-cliphist"
        anchors { top: true; bottom: true; left: true; right: true }

        onVisibleChanged: {
            if (!visible) return
            root.detailFocused     = false
            root.fullscreenShowing = false
            list.reset()
            list.load()
            helpOverlay.close()
            fsViewer.reset()
            normalModeHandler.forceActiveFocus()
        }

        // Backdrop
        Rectangle {
            anchors.fill: parent
            color: "#99000000"
            MouseArea { anchors.fill: parent; onClicked: root.showing = false }
        }

        // Panel
        Rectangle {
            id: panel
            width: parent.width * 0.5
            height: parent.height * 0.7
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: parent.height * 0.06
            color: cfg.color.base00
            radius: 12
            clip: true

            MouseArea { anchors.fill: parent }

            // Key dispatcher — holds focus in all non-insert modes
            Item {
                id: normalModeHandler
                anchors.fill: parent

                Keys.onPressed: (event) => {
                    if (event.key === Qt.Key_Shift || event.key === Qt.Key_Control ||
                        event.key === Qt.Key_Alt   || event.key === Qt.Key_Meta) return

                    if (helpOverlay.showing) {
                        if (helpOverlay.handleKey(event)) event.accepted = true
                        return
                    }
                    if (root.fullscreenShowing) {
                        if (fsViewer.handleKey(event)) {
                            event.accepted = true
                        } else if (event.text === "y") {
                            if (list.selectedEntry !== "")
                                { list.flash(list.selectedIndex); pasteEntry(list.selectedEntry) }
                            event.accepted = true
                        } else if (event.key === Qt.Key_Escape) {
                            root.fullscreenShowing = false; fsViewer.reset(); event.accepted = true
                        }
                        return
                    }
                    if (root.detailFocused) {
                        if (preview.handleKey(event)) event.accepted = true
                        return
                    }
                    if (list.handleKey(event)) {
                        event.accepted = true
                    } else if (event.text === "?") {
                        helpOverlay.open(); event.accepted = true
                    }
                }
            }

            // Footer (anchored to bottom)
            Item {
                id: footer
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 28

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    text: {
                        if (root.fullscreenShowing)
                            return preview.modeText !== ""
                                ? preview.hintText
                                : "Esc back  \u00b7  hjkl/w/b/e cursor  \u00b7  0/$  line  \u00b7  v/V/Ctrl+V visual  \u00b7  y copy"
                        if (root.detailFocused)
                            return preview.modeText !== ""
                                ? preview.hintText
                                : "Tab/Esc list  \u00b7  hjkl/w/b/e cursor  \u00b7  0/$  line  \u00b7  v/V/Ctrl+V visual  \u00b7  Enter fullscreen  \u00b7  y copy"
                        return list.hintText
                    }
                    color: cfg.color.base03
                    font.family: cfg.fontFamily
                    font.pixelSize: cfg.fontSize - 3
                }
                Text {
                    anchors.right: parent.right
                    anchors.rightMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    text: list.filteredEntries.length + " entries"
                    color: cfg.color.base03
                    font.family: cfg.fontFamily
                    font.pixelSize: cfg.fontSize - 3
                }
            }

            // Content area: list + detail side-by-side
            Item {
                id: contentArea
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: footer.top

                ClipList {
                    id: list
                    x: 0; y: 0
                    width: Math.round(parent.width * 0.4)
                    height: parent.height

                    onSearchEscapePressed: { enterNormalMode(); normalModeHandler.forceActiveFocus() }
                    onOpenDetail:          root.detailFocused = true
                    onCloseRequested:      root.showing = false
                    onYankEntryRequested:  (rawLine) => pasteEntry(rawLine)
                }

                // Focus divider
                Rectangle {
                    x: list.width
                    width: 1
                    height: parent.height
                    color: root.detailFocused ? cfg.color.base0D : cfg.color.base02
                }

                ClipPreview {
                    id: preview
                    x: list.width + 1
                    width: parent.width - list.width - 1
                    height: parent.height

                    entry:   list.selectedEntry
                    focused: root.detailFocused

                    onExitFocus:           { root.detailFocused = false; normalModeHandler.forceActiveFocus() }
                    onFullscreenRequested: { root.fullscreenShowing = true; fsViewer.reset() }
                    onYankEntryRequested:  (rawLine) => pasteEntry(rawLine)
                    onYankTextRequested:   (text)    => yankText(text)
                }

                // Fullscreen overlay (z:5, feeds from preview content)
                Rectangle {
                    anchors.fill: parent
                    visible: root.fullscreenShowing
                    color: cfg.color.base00
                    z: 5

                    TextViewer {
                        id: fsViewer
                        anchors.fill: parent

                        text:        preview.text
                        isImage:     preview.isImage
                        imageSource: preview.imageSource
                        focused:     root.fullscreenShowing
                        loading:     false

                        textColor:          cfg.color.base05
                        selectionColor:     cfg.color.base0D
                        selectionTextColor: cfg.color.base00
                        cursorColor:        cfg.color.base07
                        dimColor:           cfg.color.base03
                        fontFamily:         cfg.fontFamily
                        fontSize:           cfg.fontSize

                        onYankTextRequested: (t) => root.yankText(t)
                    }
                }
            }

            // Confirm-delete overlay
            Overlay {
                anchors.fill: parent
                showing:    list._confirmingDelete
                title:      "CONFIRM DELETE"
                titleColor: cfg.color.base08
                footerText: "y  confirm  \u00b7  Esc  cancel"
                maxWidth:   320
                bgColor:    cfg.color.base01
                headerBg:   cfg.color.base02
                dimColor:   cfg.color.base03
                fontFamily: cfg.fontFamily
                fontSize:   cfg.fontSize

                Item {
                    width: parent.width
                    height: 52
                    Text {
                        anchors.centerIn: parent
                        text: {
                            const n = list._pendingDeleteLines.length
                            return n === 1 ? "Delete this entry?" : "Delete " + n + " entries?"
                        }
                        color: cfg.color.base05
                        font.family: cfg.fontFamily
                        font.pixelSize: cfg.fontSize
                    }
                }
            }

            // Help overlay (backdrop + popup at z:9/10, fills panel)
            HelpOverlay {
                id: helpOverlay
                anchors.fill: parent

                sections: [{
                    title: "NORMAL MODE",
                    bindings: [
                        { key: "j / \u2193", desc: "down" },
                        { key: "k / \u2191", desc: "up" },
                        { key: "gg",         desc: "jump to top" },
                        { key: "G",          desc: "jump to bottom" },
                        { key: "Ctrl+D",     desc: "half-page down" },
                        { key: "Ctrl+U",     desc: "half-page up" },
                        { key: "y",          desc: "copy to clipboard" },
                        { key: "d",          desc: "delete entry" },
                        { key: "v",          desc: "visual select mode" },
                        { key: "p",          desc: "pin / unpin entry" },
                        { key: "Tab",        desc: "focus detail pane" },
                        { key: "Enter",      desc: "fullscreen detail" },
                        { key: "Tab / Esc",  desc: "focus list (from detail)" },
                        { key: "/",          desc: "focus search" },
                        { key: "Esc",        desc: "close" }
                    ]
                }, {
                    title: "VISUAL MODE",
                    bindings: [
                        { key: "j / \u2193", desc: "down" },
                        { key: "k / \u2191", desc: "up" },
                        { key: "gg",         desc: "jump to top" },
                        { key: "G",          desc: "jump to bottom" },
                        { key: "Ctrl+D",     desc: "half-page down" },
                        { key: "Ctrl+U",     desc: "half-page up" },
                        { key: "d",          desc: "delete selected entries" },
                        { key: "v / Esc",    desc: "normal mode" }
                    ]
                }, {
                    title: "INSERT MODE",
                    bindings: [
                        { key: "Esc",    desc: "normal mode" },
                        { key: "Ctrl+A", desc: "cursor to start" },
                        { key: "Ctrl+E", desc: "cursor to end" },
                        { key: "Ctrl+F", desc: "cursor forward" },
                        { key: "Ctrl+B", desc: "cursor back" },
                        { key: "Ctrl+D", desc: "delete char forward" },
                        { key: "Ctrl+K", desc: "delete to end of line" },
                        { key: "Ctrl+W", desc: "delete word back" },
                        { key: "Ctrl+U", desc: "delete to line start" }
                    ]
                }]

                bgColor:    cfg.color.base01
                headerBg:   cfg.color.base02
                textColor:  cfg.color.base05
                keyColor:   cfg.color.base0D
                dimColor:   cfg.color.base03
                fontFamily: cfg.fontFamily
                fontSize:   cfg.fontSize
            }
        }
    }
}
