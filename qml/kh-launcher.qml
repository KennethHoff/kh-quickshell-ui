// Application launcher — orchestrator.
//
// Daemon: quickshell -c kh-launcher
// Toggle: quickshell ipc -c kh-launcher call launcher toggle
//
// This file owns: window, IPC, global launch dispatch, focus routing, and
// HelpOverlay. All app list and actions logic lives in AppList.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "./lib"

ShellRoot {
    id: root

    NixConfig { id: cfg }
    NixBins   { id: bin }

    property bool showing: false

    // ── Launch ────────────────────────────────────────────────────────────────
    function launchApp(exec, terminal, workspace) {
        let cmd = exec
        if (terminal) cmd = bin.kitty + " -- bash -c " + JSON.stringify(cmd)

        if (workspace > 0) {
            launchProcess.command = [
                bin.hyprctl, "dispatch", "exec",
                "[workspace " + workspace + "] " + cmd
            ]
        } else {
            launchProcess.command = [bin.bash, "-c", cmd + " &>/dev/null &"]
        }
        launchProcess.running = true
        closeTimer.restart()
    }

    Process { id: launchProcess }
    Timer   { id: closeTimer; interval: 120; onTriggered: root.showing = false }

    // ── IPC ───────────────────────────────────────────────────────────────────
    IpcHandler {
        target: "launcher"
        readonly property bool   showing:     root.showing
        readonly property string mode:        list.mode
        readonly property var    selectedApp: list.selectedApp
        readonly property var    actions:     list._actions

        function toggle()           { root.showing = !root.showing }
        function launch(): void {
            if (list.selectedApp) root.launchApp(list.selectedApp.exec, list.selectedApp.terminal, 0)
        }
        function launchOnWorkspace(n: int): void {
            if (list.selectedApp) root.launchApp(list.selectedApp.exec, list.selectedApp.terminal, n)
        }
        function enterActionsMode() { list.enterActionsMode() }
        function setMode(m: string) {
            if (m === "insert") { list.enterInsertMode() }
            else { list.enterNormalMode(); normalModeHandler.forceActiveFocus() }
        }
        function nav(dir: string) {
            const d = dir.toLowerCase()
            if      (d === "down")   list.navDown()
            else if (d === "up")     list.navUp()
            else if (d === "top")    list.navTop()
            else if (d === "bottom") list.navBottom()
        }
        function key(k: string) {
            const lk = k.toLowerCase()
            if (lk === "?") {
                helpOverlay.showing ? helpOverlay.close() : helpOverlay.open()
            } else if (lk === "/" && helpOverlay.showing) {
                helpOverlay._filtering = true; helpOverlay._filterText = ""
            } else if (lk === "escape" || lk === "esc") {
                if (helpOverlay.showing)    helpOverlay.close()
                else                        list.handleIpcKey(k)
            } else if (lk === "enter" || lk === "return") {
                list.handleIpcKey(k)
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
        namespace: "kh-launcher"
        anchors { top: true; bottom: true; left: true; right: true }

        onVisibleChanged: {
            if (!visible) return
            list.reset()
            list.load()
            helpOverlay.close()
            normalModeHandler.forceActiveFocus()
            // insert mode is set in reset(); focus is given after load completes
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
            width: Math.round(parent.width * 0.42)
            height: Math.round(parent.height * 0.65)
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: Math.round(parent.height * 0.08)
            color: cfg.color.base00
            radius: 12
            clip: true

            MouseArea { anchors.fill: parent }

            // Key dispatcher — holds focus in normal/actions mode
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
                    if (list.handleKey(event)) {
                        event.accepted = true
                    } else if (event.text === "?") {
                        helpOverlay.open(); event.accepted = true
                    } else if (event.key === Qt.Key_Slash) {
                        list.enterInsertMode(); event.accepted = true
                    }
                }
            }

            // Footer
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
                    text: list.hintText
                    color: cfg.color.base03
                    font.family: cfg.fontFamily
                    font.pixelSize: cfg.fontSize - 3
                }
                Text {
                    anchors.right: parent.right
                    anchors.rightMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    text: list.filteredCount + " apps"
                    color: cfg.color.base03
                    font.family: cfg.fontFamily
                    font.pixelSize: cfg.fontSize - 3
                }
            }

            // Content
            AppList {
                id: list
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: footer.top

                onSearchEscapePressed: { enterNormalMode(); normalModeHandler.forceActiveFocus() }
                onCloseRequested:      root.showing = false
                onLaunchRequested:     (exec, terminal, workspace) => root.launchApp(exec, terminal, workspace)
            }

            // Help overlay
            HelpOverlay {
                id: helpOverlay
                anchors.fill: parent

                sections: list.mode === "actions" ? [{
                    title: "ACTIONS MODE",
                    bindings: [
                        { key: "j / \u2193", desc: "down" },
                        { key: "k / \u2191", desc: "up" },
                        { key: "gg",         desc: "jump to top" },
                        { key: "G",          desc: "jump to bottom" },
                        { key: "Ctrl+D",     desc: "half-page down" },
                        { key: "Ctrl+U",     desc: "half-page up" },
                        { key: "Enter",      desc: "launch action" },
                        { key: "Ctrl+1\u20139", desc: "launch on workspace" },
                        { key: "h / Esc",    desc: "back to app list" }
                    ]
                }] : [{
                    title: "NORMAL MODE",
                    bindings: [
                        { key: "j / \u2193", desc: "down" },
                        { key: "k / \u2191", desc: "up" },
                        { key: "gg",         desc: "jump to top" },
                        { key: "G",          desc: "jump to bottom" },
                        { key: "Ctrl+D",     desc: "half-page down" },
                        { key: "Ctrl+U",     desc: "half-page up" },
                        { key: "Enter",      desc: "launch app" },
                        { key: "l / Tab",    desc: "actions for app" },
                        { key: "Ctrl+1\u20139", desc: "launch on workspace" },
                        { key: "/",          desc: "focus search" },
                        { key: "q / Esc",    desc: "close" }
                    ]
                }, {
                    title: "INSERT MODE",
                    bindings: [
                        { key: "Esc / Enter", desc: "normal mode" },
                        { key: "Ctrl+A",      desc: "cursor to start" },
                        { key: "Ctrl+E",      desc: "cursor to end" },
                        { key: "Ctrl+F",      desc: "cursor forward" },
                        { key: "Ctrl+B",      desc: "cursor back" },
                        { key: "Ctrl+D",      desc: "delete char forward" },
                        { key: "Ctrl+K",      desc: "delete to end of line" },
                        { key: "Ctrl+W",      desc: "delete word back" },
                        { key: "Ctrl+U",      desc: "delete to line start" }
                    ]
                }, {
                    title: "SEARCH FILTERS",
                    bindings: [
                        { key: "'foo",  desc: "exact substring match" },
                        { key: "^foo",  desc: "name prefix match" },
                        { key: "$foo",  desc: "name suffix match" },
                        { key: "!foo",  desc: "exclude matching apps" },
                        { key: "a b",   desc: "AND: must match both tokens" }
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
