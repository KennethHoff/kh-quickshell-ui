// Application launcher.
//
// Daemon mode: quickshell -p <config-dir>
// Toggle:      quickshell ipc call launcher toggle
//
// Keys (list):    Type to search · ↑↓ navigate · Enter launch · Tab actions
//                 Ctrl+1–9 workspace · ? help
// Keys (actions): ↑↓ navigate · Enter launch action · Tab / Esc back
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "./lib"

ShellRoot {
    id: root

    // ── Nix config ───────────────────────────────────────────────────────────
    NixConfig { id: cfg }
    NixBins   { id: bin }

    // ── Lib ──────────────────────────────────────────────────────────────────
    LauncherFilter { id: launcherFilter }
    ExecPrep       { id: execPrep }

    // ── State ────────────────────────────────────────────────────────────────
    property bool   showing: false
    property string view: "list"   // "list" | "actions" | "help"
    property int    actionIndex: 0
    property var    actionEntry: null
    property string helpFilter: ""
    signal appLaunched(int idx)
    signal actionLaunched(int idx)

    // ── Filtering ────────────────────────────────────────────────────────────
    property var filteredApps: launcherFilter.filterApps(
        DesktopEntries.applications.values,
        searchField.text
    )

    // ── Actions ──────────────────────────────────────────────────────────────
    function launch(entry) {
        launchProcess.command = [
            bin.hyprctl, "dispatch", "exec",
            execPrep.buildExec(entry, bin.kitty)
        ]
        root.appLaunched(resultList.currentIndex)
        launchProcess.running = true
        closeTimer.restart()
    }

    function launchAction(action) {
        root.actionLaunched(root.actionIndex)
        action.execute()
        closeTimer.restart()
    }

    function launchToWorkspace(entry, workspace) {
        launchProcess.command = [
            bin.hyprctl, "dispatch", "exec",
            execPrep.workspaceExec(entry, workspace, bin.kitty)
        ]
        root.appLaunched(resultList.currentIndex)
        launchProcess.running = true
        closeTimer.restart()
    }

    function enterActionMode() {
        const apps = root.filteredApps
        if (resultList.currentIndex < 0 || resultList.currentIndex >= apps.length) return
        const entry = apps[resultList.currentIndex]
        if (!entry || !entry.actions || entry.actions.length === 0) return
        root.actionEntry = entry
        root.actionIndex = 0
        root.view = "actions"
    }

    function exitActionMode() {
        root.view = "list"
        root.actionEntry = null
    }

    // ── Processes / timers ───────────────────────────────────────────────────
    Process { id: launchProcess }

    Timer {
        id: closeTimer
        interval: 200
        repeat: false
        onTriggered: root.showing = false
    }

    IpcHandler {
        target: "launcher"
        readonly property bool   showing: root.showing
        readonly property string view:    root.view
        function toggle()              { root.showing = !root.showing }
        function setView(v: string)    { root.view = v }
        function nav(dir: string) {
            if (dir === "down") {
                if (root.view === "actions") {
                    if (root.actionEntry && root.actionIndex < root.actionEntry.actions.length - 1)
                        root.actionIndex++
                } else if (root.view === "list") {
                    if (resultList.currentIndex < resultList.count - 1) resultList.currentIndex++
                }
            } else if (dir === "up") {
                if (root.view === "actions") {
                    if (root.actionIndex > 0) root.actionIndex--
                } else if (root.view === "list") {
                    if (resultList.currentIndex > 0) resultList.currentIndex--
                }
            }
        }
        function type(text: string) {
            for (let i = 0; i < text.length; i++) {
                const ch = text[i]
                if (ch === "?") {
                    if (root.view === "help") { root.view = "list"; root.helpFilter = "" }
                    else if (root.view === "list") { root.view = "help"; root.helpFilter = "" }
                } else if (root.view === "help") {
                    root.helpFilter += ch
                } else {
                    searchField.text += ch
                }
            }
        }
        function key(k: string) {
            const lk = k.toLowerCase()
            if (lk === "escape" || lk === "esc") {
                if (root.view === "help") {
                    if (root.helpFilter) root.helpFilter = ""; else root.view = "list"
                } else if (root.view === "actions") root.exitActionMode()
                else root.showing = false
            } else if (lk === "enter" || lk === "return") {
                if (root.view === "actions") {
                    if (root.actionEntry && root.actionIndex >= 0 &&
                            root.actionIndex < root.actionEntry.actions.length)
                        root.launchAction(root.actionEntry.actions[root.actionIndex])
                } else if (root.view === "list") {
                    const apps = root.filteredApps
                    if (resultList.currentIndex >= 0 && resultList.currentIndex < apps.length)
                        root.launch(apps[resultList.currentIndex])
                }
            } else if (lk === "tab") {
                if (root.view === "actions") root.exitActionMode()
                else root.enterActionMode()
            } else if (lk === "backspace") {
                if (root.view === "help") root.helpFilter = root.helpFilter.slice(0, -1)
                else searchField.text = searchField.text.slice(0, -1)
            } else if (lk === "ctrl+w") {
                if (root.view === "help") root.helpFilter = root.helpFilter.replace(/\S+\s*$/, "")
                else searchField.text = searchField.text.replace(/\S+\s*$/, "")
            }
        }
    }

    // ── Window ───────────────────────────────────────────────────────────────
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
            if (visible) {
                searchField.text = ""
                root.view = "list"
                root.actionEntry = null
                searchField.forceActiveFocus()
                resultList.currentIndex = 0
            }
        }

        // Backdrop ────────────────────────────────────────────────────────────
        Rectangle {
            anchors.fill: parent
            color: "#99000000"
            MouseArea {
                anchors.fill: parent
                onClicked: root.showing = false
            }
        }

        // Panel ───────────────────────────────────────────────────────────────
        Rectangle {
            id: panel
            width: 560
            height: column.y + column.implicitHeight + 8
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 100
            color: cfg.color.base00
            radius: 12
            clip: true

            MouseArea { anchors.fill: parent }

            Column {
                id: column
                x: 8; y: 8
                width: parent.width - 16
                spacing: 4

                // Search box ──────────────────────────────────────────────────
                Rectangle {
                    id: searchBox
                    width: parent.width
                    height: 44
                    color: cfg.color.base01
                    radius: 8

                    TextInput {
                        id: searchField
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        color: root.view === "list" ? cfg.color.base05 : "transparent"
                        font.family: cfg.fontFamily
                        font.pixelSize: cfg.fontSize
                        clip: true
                        verticalAlignment: TextInput.AlignVCenter
                        readOnly: root.view !== "list"

                        Text {
                            anchors.fill: parent
                            text: root.view === "help"
                                ? (root.helpFilter ? root.helpFilter : "Filter shortcuts...")
                                : "Search applications..."
                            color: (root.view === "help") && root.helpFilter
                                ? cfg.color.base05
                                : cfg.color.base03
                            font.family: cfg.fontFamily
                            font.pixelSize: cfg.fontSize
                            verticalAlignment: Text.AlignVCenter
                            visible: root.view === "help" || (root.view === "list" && !searchField.text)
                        }

                        onTextChanged: resultList.currentIndex = 0

                        Keys.onEscapePressed: {
                            if (root.view === "help") {
                                if (root.helpFilter) root.helpFilter = ""
                                else root.view = "list"
                                return
                            }
                            if (root.view === "actions") root.exitActionMode()
                            else root.showing = false
                        }
                        Keys.onReturnPressed: {
                            if (root.view === "help") return
                            if (root.view === "actions") {
                                if (root.actionEntry && root.actionIndex >= 0 &&
                                        root.actionIndex < root.actionEntry.actions.length)
                                    root.launchAction(root.actionEntry.actions[root.actionIndex])
                            } else {
                                const apps = root.filteredApps
                                if (resultList.currentIndex >= 0 && resultList.currentIndex < apps.length)
                                    root.launch(apps[resultList.currentIndex])
                            }
                        }
                        Keys.onUpPressed: {
                            if (root.view === "help") return
                            if (root.view === "actions") {
                                if (root.actionIndex > 0) root.actionIndex--
                            } else {
                                if (resultList.currentIndex > 0) resultList.currentIndex--
                            }
                        }
                        Keys.onDownPressed: {
                            if (root.view === "help") return
                            if (root.view === "actions") {
                                if (root.actionEntry &&
                                        root.actionIndex < root.actionEntry.actions.length - 1)
                                    root.actionIndex++
                            } else {
                                if (resultList.currentIndex < resultList.count - 1)
                                    resultList.currentIndex++
                            }
                        }
                        Keys.onPressed: (event) => {
                            if (event.key === Qt.Key_Shift || event.key === Qt.Key_Control ||
                                event.key === Qt.Key_Alt  || event.key === Qt.Key_Meta) return
                            if (event.text === "?") {
                                if (root.view === "help") {
                                    root.view = "list"; root.helpFilter = ""
                                } else if (root.view === "list") {
                                    root.view = "help"; root.helpFilter = ""
                                }
                                event.accepted = true
                                return
                            }
                            if (root.view === "help") {
                                if (event.key === Qt.Key_Backspace)
                                    root.helpFilter = root.helpFilter.slice(0, -1)
                                else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_W)
                                    root.helpFilter = root.helpFilter.replace(/\S+\s*$/, "")
                                else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32)
                                    root.helpFilter += event.text
                                if (event.key !== Qt.Key_Escape) event.accepted = true
                                return
                            }
                            if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_W) {
                                searchField.text = searchField.text.replace(/\S+\s*$/, "")
                                event.accepted = true
                                return
                            }
                            if (event.key === Qt.Key_Tab) {
                                if (root.view === "actions") root.exitActionMode()
                                else root.enterActionMode()
                                event.accepted = true
                            } else if (root.view === "list" &&
                                       (event.modifiers & Qt.ControlModifier) &&
                                       event.key >= Qt.Key_1 && event.key <= Qt.Key_9) {
                                const ws = event.key - Qt.Key_0
                                const apps = root.filteredApps
                                if (resultList.currentIndex >= 0 && resultList.currentIndex < apps.length)
                                    root.launchToWorkspace(apps[resultList.currentIndex], ws)
                                event.accepted = true
                            }
                        }
                    }

                    // Action mode breadcrumb
                    RowLayout {
                        visible: root.view === "actions"
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        spacing: 10

                        Image {
                            Layout.preferredWidth: 22
                            Layout.preferredHeight: 22
                            source: root.actionEntry && root.actionEntry.icon
                                ? Quickshell.iconPath(root.actionEntry.icon) : ""
                            fillMode: Image.PreserveAspectFit
                            smooth: true; mipmap: true
                        }

                        Text {
                            Layout.fillWidth: true
                            text: root.actionEntry ? root.actionEntry.name : ""
                            color: cfg.color.base05
                            font.family: cfg.fontFamily
                            font.pixelSize: cfg.fontSize
                        }

                        Text {
                            text: "Tab / Esc \u2190 back"
                            color: cfg.color.base03
                            font.family: cfg.fontFamily
                            font.pixelSize: cfg.fontSize - 3
                        }
                    }
                }

                // App list ────────────────────────────────────────────────────
                ListView {
                    id: resultList
                    width: parent.width
                    height: Math.min(contentHeight, 400)
                    visible: root.view === "list"
                    clip: true
                    currentIndex: 0
                    model: root.filteredApps
                    highlightMoveDuration: 0

                    onCountChanged: if (count > 0 && currentIndex < 0) currentIndex = 0

                    Text {
                        anchors.centerIn: parent
                        visible: resultList.count === 0 && searchField.text.length > 0
                        text: "No results"
                        color: cfg.color.base03
                        font.family: cfg.fontFamily
                        font.pixelSize: cfg.fontSize
                    }

                    delegate: Item {
                        id: delegateRoot
                        required property var modelData
                        required property int index
                        width: resultList.width
                        height: 50

                        readonly property bool isCurrent: resultList.currentIndex === index
                        readonly property bool hasActions: modelData.actions && modelData.actions.length > 0

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 2
                            color: delegateRoot.isCurrent
                                ? cfg.color.base02
                                : (hoverArea.containsMouse ? cfg.color.base01 : "transparent")
                            radius: 6

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                spacing: 10

                                Image {
                                    Layout.preferredWidth: 28
                                    Layout.preferredHeight: 28
                                    source: delegateRoot.modelData.icon
                                        ? Quickshell.iconPath(delegateRoot.modelData.icon) : ""
                                    fillMode: Image.PreserveAspectFit
                                    smooth: true; mipmap: true; asynchronous: true
                                }

                                Column {
                                    Layout.fillWidth: true
                                    spacing: 2

                                    Text {
                                        text: delegateRoot.modelData.name
                                        color: cfg.color.base05
                                        font.family: cfg.fontFamily
                                        font.pixelSize: cfg.fontSize
                                        elide: Text.ElideRight
                                        width: parent.width
                                    }

                                    Text {
                                        visible: delegateRoot.modelData.comment !== ""
                                        text: delegateRoot.modelData.comment
                                        color: cfg.color.base03
                                        font.family: cfg.fontFamily
                                        font.pixelSize: cfg.fontSize - 2
                                        elide: Text.ElideRight
                                        width: parent.width
                                    }
                                }

                                Text {
                                    visible: delegateRoot.isCurrent && delegateRoot.hasActions
                                    text: "Tab"
                                    color: cfg.color.base03
                                    font.family: cfg.fontFamily
                                    font.pixelSize: cfg.fontSize - 3
                                }
                            }

                            MouseArea {
                                id: hoverArea
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: {
                                    resultList.currentIndex = delegateRoot.index
                                    root.launch(delegateRoot.modelData)
                                }
                            }

                            Rectangle {
                                id: flashOverlay
                                anchors.fill: parent
                                radius: 6
                                color: cfg.color.base0D
                                opacity: 0
                                SequentialAnimation {
                                    id: blinkAnim
                                    NumberAnimation { target: flashOverlay; property: "opacity"; to: 0.55; duration: 60;  easing.type: Easing.OutQuad }
                                    NumberAnimation { target: flashOverlay; property: "opacity"; to: 0;    duration: 140; easing.type: Easing.InQuad }
                                }
                            }
                            Connections {
                                target: root
                                function onAppLaunched(idx) { if (idx === delegateRoot.index) blinkAnim.restart() }
                            }
                        }
                    }
                }

                // Help overlay ────────────────────────────────────────────────
                Column {
                    id: helpContent
                    visible: root.view === "help"
                    width: parent.width
                    spacing: 0
                    topPadding: 4
                    bottomPadding: 4

                    component ShortcutRow: Row {
                        property string shortcut: ""
                        property string description: ""
                        width: helpContent.width
                        height: 26
                        visible: {
                            const f = root.helpFilter.toLowerCase()
                            if (!f) return true
                            return shortcut.toLowerCase().includes(f) || description.toLowerCase().includes(f)
                        }
                        Text {
                            width: 130
                            text: shortcut
                            color: cfg.color.base03
                            font.family: cfg.fontFamily
                            font.pixelSize: cfg.fontSize - 1
                            horizontalAlignment: Text.AlignRight
                        }
                        Item { width: 14; height: 1 }
                        Text {
                            text: description
                            color: cfg.color.base05
                            font.family: cfg.fontFamily
                            font.pixelSize: cfg.fontSize - 1
                        }
                    }

                    component SectionLabel: Text {
                        width: helpContent.width
                        visible: !root.helpFilter
                        color: cfg.color.base03
                        font.family: cfg.fontFamily
                        font.pixelSize: cfg.fontSize - 3
                        topPadding: 8
                        bottomPadding: 4
                    }

                    SectionLabel { text: "App mode" }
                    ShortcutRow { shortcut: "\u2191 / \u2193"; description: "Navigate" }
                    ShortcutRow { shortcut: "Enter";           description: "Launch" }
                    ShortcutRow { shortcut: "Esc";             description: "Close" }
                    ShortcutRow { shortcut: "Tab";             description: "Open actions" }
                    ShortcutRow { shortcut: "Ctrl+1\u20139";   description: "Launch to workspace" }
                    ShortcutRow { shortcut: "?";               description: "Toggle this help" }

                    SectionLabel { text: "Action mode  (Tab to enter)" }
                    ShortcutRow { shortcut: "\u2191 / \u2193"; description: "Navigate actions" }
                    ShortcutRow { shortcut: "Enter";           description: "Launch action" }
                    ShortcutRow { shortcut: "Tab / Esc";       description: "Back to app list" }

                    Item { width: 1; height: 4 }
                }

                // Footer ──────────────────────────────────────────────────────
                Item {
                    width: parent.width
                    height: 28
                    visible: root.view === "list"
                    Text {
                        anchors.centerIn: parent
                        text: "Ctrl+1\u20139  workspace  \u00b7  ?  help"
                        color: cfg.color.base03
                        font.family: cfg.fontFamily
                        font.pixelSize: cfg.fontSize - 3
                    }
                }

                // Action list ─────────────────────────────────────────────────
                ListView {
                    id: actionList
                    width: parent.width
                    height: Math.min(contentHeight, 300)
                    visible: root.view === "actions"
                    clip: true
                    currentIndex: root.actionIndex
                    model: root.view === "actions" && root.actionEntry
                        ? root.actionEntry.actions : []
                    highlightMoveDuration: 0

                    delegate: Item {
                        id: actionDelegate
                        required property var modelData
                        required property int index
                        width: actionList.width
                        height: 44

                        readonly property bool isCurrent: root.actionIndex === index

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 2
                            color: actionDelegate.isCurrent
                                ? cfg.color.base02
                                : (actionHover.containsMouse ? cfg.color.base01 : "transparent")
                            radius: 6

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                spacing: 10

                                Image {
                                    Layout.preferredWidth: 28
                                    Layout.preferredHeight: 28
                                    source: actionDelegate.modelData.icon
                                        ? Quickshell.iconPath(actionDelegate.modelData.icon) : ""
                                    fillMode: Image.PreserveAspectFit
                                    smooth: true; mipmap: true; asynchronous: true
                                    visible: actionDelegate.modelData.icon !== ""
                                }

                                Item {
                                    Layout.preferredWidth: 28
                                    Layout.preferredHeight: 28
                                    visible: actionDelegate.modelData.icon === ""
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: actionDelegate.modelData.name
                                    color: cfg.color.base05
                                    font.family: cfg.fontFamily
                                    font.pixelSize: cfg.fontSize
                                    elide: Text.ElideRight
                                }
                            }

                            MouseArea {
                                id: actionHover
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: {
                                    root.actionIndex = actionDelegate.index
                                    root.launchAction(actionDelegate.modelData)
                                }
                            }

                            Rectangle {
                                id: actionFlashOverlay
                                anchors.fill: parent
                                radius: 6
                                color: cfg.color.base0D
                                opacity: 0
                                SequentialAnimation {
                                    id: actionBlinkAnim
                                    NumberAnimation { target: actionFlashOverlay; property: "opacity"; to: 0.55; duration: 60;  easing.type: Easing.OutQuad }
                                    NumberAnimation { target: actionFlashOverlay; property: "opacity"; to: 0;    duration: 140; easing.type: Easing.InQuad }
                                }
                            }
                            Connections {
                                target: root
                                function onActionLaunched(idx) { if (idx === actionDelegate.index) actionBlinkAnim.restart() }
                            }
                        }
                    }
                }
            }
        }
    }
}
