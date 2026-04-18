// Application launcher — orchestrator.
//
// Daemon: quickshell -c kh-launcher
// Toggle: quickshell ipc -c kh-launcher call launcher toggle
//
// This file owns: window, IPC, global launch dispatch, focus routing, and
// HelpOverlay.  All mode, item, and navigation logic lives in ModeList.
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

    Process { id: launchProcess }
    Timer   { id: closeTimer; interval: 120; onTriggered: functionality.close() }

    // ── Launch ────────────────────────────────────────────────────────────────
    QtObject {
        id: impl
        function launchCallback(callback, workspace): void {
            if (!callback) return
            if (workspace > 0) {
                launchProcess.command = [
                    bin.hyprctl, "dispatch", "exec",
                    "[workspace " + workspace + "] " + callback
                ]
            } else {
                launchProcess.command = [bin.bash, "-c", callback + " &>/dev/null &"]
            }
            launchProcess.running = true
            closeTimer.restart()
        }
    }

    // ── Functionality ─────────────────────────────────────────────────────────
    QtObject {
        id: functionality

        // ui+ipc
        function toggle(): void                      { root.showing = !root.showing }
        // ipc only
        function open(): void                        { root.showing = true }
        // ui+ipc
        function close(): void                       { root.showing = false }
        // ipc only
        function launch(): void                      { if (list.selectedItem) impl.launchCallback(list.selectedItem.callback, 0) }
        // ipc only
        function launchOnWorkspace(n: int): void     { if (list.selectedItem) impl.launchCallback(list.selectedItem.callback, n) }
        // ipc only
        function enterActionsMode(): void            { list.enterActionsMode() }
        // ui+ipc (via setMode / handleKeyEvent)
        function enterInsertMode(): void             { list.enterInsertMode() }
        // ui+ipc (via setMode / handleKeyEvent)
        function enterNormalMode(): void             { list.enterNormalMode(); normalModeHandler.forceActiveFocus() }
        // ipc only
        function setMode(m: string): void            { if (m === "insert") enterInsertMode(); else enterNormalMode() }
        // ipc only
        function nav(dir: string): void {
            const d = dir.toLowerCase()
            if      (d === "down")   list.navDown()
            else if (d === "up")     list.navUp()
            else if (d === "top")    list.navTop()
            else if (d === "bottom") list.navBottom()
        }
        // ui+ipc (via key / handleKeyEvent)
        function openHelp(): void                    { helpOverlay.open() }
        // ui+ipc (via key / handleKeyEvent)
        function closeHelp(): void                   { helpOverlay.close() }
        // ipc only (via key)
        function toggleHelp(): void                  { helpOverlay.showing ? helpOverlay.close() : helpOverlay.open() }
        // ipc only
        function type(text: string): void {
            if (helpOverlay.showing) { helpOverlay._filtering = true; helpOverlay._filterText += text }
            else                     list.typeText(text)
        }
        // ipc only
        function key(k: string): void {
            const lk = k.toLowerCase()
            if      (lk === "?")                       toggleHelp()
            else if (lk === "/" && helpOverlay.showing) { helpOverlay._filtering = true; helpOverlay._filterText = "" }
            else if (lk === "escape" || lk === "esc")  { if (helpOverlay.showing) closeHelp(); else list.handleIpcKey(k) }
            else                                        list.handleIpcKey(k)
        }
        // ipc only — activate a named mode (registered or ad-hoc); opens the launcher
        function activateMode(name: string): void {
            list.activateMode(name)
            root.showing = true
            normalModeHandler.forceActiveFocus()
        }
        // ipc only — push an item into a named mode's buffer
        function addItem(mode: string, label: string, description: string, icon: string, callback: string): void {
            list.addItem(mode, label, description, icon, callback, label)
        }
        // ipc only — push an item with an explicit id into a named mode's buffer
        function addItemWithId(mode: string, label: string, description: string, icon: string, callback: string, id: string): void {
            list.addItem(mode, label, description, icon, callback, id)
        }
        // ipc only — signal all items for the named mode have been pushed
        function itemsReady(mode: string): void      { list.itemsReady(mode) }
        // ipc only — return to the default mode
        function returnToDefault(): void             { list.activateDefaultMode() }
        // ipc only — register or replace a mode in the runtime registry
        function registerMode(name: string, script: string, frecency: bool, hasActions: bool, placeholder: string): void {
            list.registerMode(name, script, frecency, hasActions, placeholder)
        }
        // ipc only — remove a mode from the runtime registry
        function removeMode(name: string): void      { list.removeMode(name) }
        // ipc only — list registered mode names
        function listModes(): string                 { return list.listModes() }
        // ui+ipc — cycle to the next registered mode
        function nextMode(): void                    { list.nextMode() }
        // ui+ipc — cycle to the previous registered mode
        function prevMode(): void                    { list.prevMode() }
        // ui only
        function onShow(): void                      { list.reset(); list.activateDefaultMode(); helpOverlay.close(); normalModeHandler.forceActiveFocus() }
        // ui only
        function onVisibleChanged(): void            { if (root.showing) onShow() }
        // ui only
        function onLaunchRequested(callback, workspace): void { impl.launchCallback(callback, workspace) }
        // ui only
        function handleKeyEvent(event): void {
            if (event.key === Qt.Key_Shift || event.key === Qt.Key_Control ||
                event.key === Qt.Key_Alt   || event.key === Qt.Key_Meta) return
            if (helpOverlay.showing)        { event.accepted = helpOverlay.handleKey(event); return }
            if (list.handleKey(event))      { event.accepted = true; return }
            if (event.text === "?")         { openHelp();        event.accepted = true; return }
            if (event.key === Qt.Key_Slash) { enterInsertMode(); event.accepted = true; return }
        }
    }

    // ── IPC ───────────────────────────────────────────────────────────────────
    IpcHandler {
        target: "launcher"
        // Window state
        readonly property bool   showing:          root.showing
        // Input mode
        readonly property string mode:             list.mode
        // Active content mode
        readonly property string activeMode:       list.activeModeName
        // Selection
        readonly property string selectedLabel:    list.selectedItem ? list.selectedItem.label : ""
        readonly property string selectedCallback: list.selectedItem ? list.selectedItem.callback : ""
        readonly property int    selectedIndex:    list.selectedItem ? list.filteredCount > 0 ? 0 : -1 : -1
        readonly property int    itemCount:        list.filteredCount
        // Last launched item label
        readonly property string lastSelection:    list.lastSelection

        // Window
        function toggle(): void                       { functionality.toggle() }
        function open(): void                         { functionality.open() }
        function close(): void                        { functionality.close() }
        // Launch
        function launch(): void                       { functionality.launch() }
        function launchOnWorkspace(n: int): void      { functionality.launchOnWorkspace(n) }
        // Input mode
        function enterActionsMode(): void             { functionality.enterActionsMode() }
        function setMode(m: string): void             { functionality.setMode(m) }
        // Navigation
        function nav(dir: string): void               { functionality.nav(dir) }
        // Key dispatch
        function key(k: string): void                 { functionality.key(k) }
        // Text input
        function type(text: string): void             { functionality.type(text) }
        // Mode system
        function activateMode(name: string): void     { functionality.activateMode(name) }
        function addItem(mode: string, label: string, description: string, icon: string, callback: string): void { functionality.addItem(mode, label, description, icon, callback) }
        function addItemWithId(mode: string, label: string, description: string, icon: string, callback: string, id: string): void { functionality.addItemWithId(mode, label, description, icon, callback, id) }
        function itemsReady(mode: string): void       { functionality.itemsReady(mode) }
        function returnToDefault(): void              { functionality.returnToDefault() }
        // Mode registry
        function registerMode(name: string, script: string, frecency: bool, hasActions: bool, placeholder: string): void { functionality.registerMode(name, script, frecency, hasActions, placeholder) }
        function removeMode(name: string): void       { functionality.removeMode(name) }
        function listModes(): string                  { return functionality.listModes() }
        function nextMode(): void                     { functionality.nextMode() }
        function prevMode(): void                     { functionality.prevMode() }
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

        // insert mode is set in reset(); focus is given after load completes
        onVisibleChanged: functionality.onVisibleChanged()

        // Backdrop
        Rectangle {
            anchors.fill: parent
            color: "#99000000"
            MouseArea { anchors.fill: parent; onClicked: functionality.close() }
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

                Keys.onPressed: (event) => functionality.handleKeyEvent(event)
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
                    text: list.filteredCount + " items"
                    color: cfg.color.base03
                    font.family: cfg.fontFamily
                    font.pixelSize: cfg.fontSize - 3
                }
            }

            // Content
            ModeList {
                id: list
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: footer.top

                onSearchEscapePressed: functionality.enterNormalMode()
                onCloseRequested:      functionality.close()
                onLaunchRequested:     (callback, workspace) => functionality.onLaunchRequested(callback, workspace)
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
                        { key: "h / Esc",    desc: "back to item list" }
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
                        { key: "Enter",      desc: "launch" },
                        { key: "l / Tab",    desc: "actions for item" },
                        { key: "[ / ]",      desc: "switch mode" },
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
                        { key: "^foo",  desc: "label prefix match" },
                        { key: "$foo",  desc: "label suffix match" },
                        { key: "!foo",  desc: "exclude matching items" },
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
