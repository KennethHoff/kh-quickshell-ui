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
    Timer   { id: closeTimer; interval: 120; onTriggered: root.core_close() }

    // ── Core actions ──────────────────────────────────────────────────────────
    function core_toggle(): void                  { showing = !showing }
    function core_open(): void                    { showing = true }
    function core_close(): void                   { showing = false }
    function core_launch(): void                  { if (list.selectedApp) launchApp(list.selectedApp.exec, list.selectedApp.terminal, 0) }
    function core_launchOnWorkspace(n: int): void { if (list.selectedApp) launchApp(list.selectedApp.exec, list.selectedApp.terminal, n) }
    function core_enterActionsMode(): void        { list.enterActionsMode() }
    function core_enterInsertMode(): void         { list.enterInsertMode() }
    function core_enterNormalMode(): void         { list.enterNormalMode(); normalModeHandler.forceActiveFocus() }
    function core_setMode(m: string): void        { if (m === "insert") core_enterInsertMode(); else core_enterNormalMode() }
    function core_navDown(): void                 { list.navDown() }
    function core_navUp(): void                   { list.navUp() }
    function core_navTop(): void                  { list.navTop() }
    function core_navBottom(): void               { list.navBottom() }
    function core_nav(dir: string): void {
        const d = dir.toLowerCase()
        if      (d === "down")   core_navDown()
        else if (d === "up")     core_navUp()
        else if (d === "top")    core_navTop()
        else if (d === "bottom") core_navBottom()
    }
    function core_openHelp(): void                { helpOverlay.open() }
    function core_closeHelp(): void               { helpOverlay.close() }
    function core_toggleHelp(): void              { helpOverlay.showing ? helpOverlay.close() : helpOverlay.open() }
    function core_type(text: string): void {
        if (helpOverlay.showing) { helpOverlay._filtering = true; helpOverlay._filterText += text }
        else                     list.typeText(text)
    }
    function core_key(k: string): void {
        const lk = k.toLowerCase()
        if      (lk === "?")                      core_toggleHelp()
        else if (lk === "/" && helpOverlay.showing) { helpOverlay._filtering = true; helpOverlay._filterText = "" }
        else if (lk === "escape" || lk === "esc") { if (helpOverlay.showing) core_closeHelp(); else list.handleIpcKey(k) }
        else                                       list.handleIpcKey(k)
    }
    function core_handleKeyEvent(event): bool {
        if (event.key === Qt.Key_Shift || event.key === Qt.Key_Control ||
            event.key === Qt.Key_Alt   || event.key === Qt.Key_Meta) return false
        if (helpOverlay.showing)        return helpOverlay.handleKey(event)
        if (list.handleKey(event))      return true
        if (event.text === "?")         { core_openHelp();        return true }
        if (event.key === Qt.Key_Slash) { core_enterInsertMode(); return true }
        return false
    }

    // ── IPC ───────────────────────────────────────────────────────────────────
    IpcHandler {
        target: "launcher"
        readonly property bool   showing:     root.showing
        readonly property string mode:        list.mode
        readonly property var    selectedApp: list.selectedApp
        readonly property var    actions:     list._actions

        function toggle(): void                  { root.core_toggle() }
        function open(): void                    { root.core_open() }
        function close(): void                   { root.core_close() }
        function launch(): void                  { root.core_launch() }
        function launchOnWorkspace(n: int): void { root.core_launchOnWorkspace(n) }
        function enterActionsMode(): void        { root.core_enterActionsMode() }
        function setMode(m: string): void        { root.core_setMode(m) }
        function nav(dir: string): void          { root.core_nav(dir) }
        function key(k: string): void            { root.core_key(k) }
        function type(text: string): void        { root.core_type(text) }
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
            MouseArea { anchors.fill: parent; onClicked: root.core_close() }
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

                Keys.onPressed: (event) => { if (root.core_handleKeyEvent(event)) event.accepted = true }
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

                onSearchEscapePressed: root.core_enterNormalMode()
                onCloseRequested:      root.core_close()
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
