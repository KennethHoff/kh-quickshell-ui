// Clipboard history viewer.
//
// Daemon: quickshell -p <config-dir>
// Toggle: quickshell ipc -c kh-cliphist call viewer toggle
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "./lib"

ShellRoot {
    id: root

    // ── Lib ──────────────────────────────────────────────────────────────────
    NixConfig     { id: cfg }
    NixBins       { id: bin }
    FuzzyScore    { id: fuzzy }
    SearchParser  { id: searchParser }
    CliphistEntry { id: clipEntry }

    // ── State ────────────────────────────────────────────────────────────────
    property bool   showing: false
    property string mode: "insert"   // "insert" | "normal"
    property var    allEntries: []
    property var    _buf: []
    property var    _fullTextCache: ({})
    property int    _cacheVersion: 0
    property bool   _pendingG: false

    signal itemPasted(int idx)

    readonly property string selectedEntry: {
        const idx = resultList.currentIndex
        const entries = root.filteredEntries
        return (idx >= 0 && idx < entries.length) ? entries[idx] : ""
    }

    // ── Filtering ────────────────────────────────────────────────────────────
    property var filteredEntries: {
        const _ = root._cacheVersion
        const parsed = searchParser.parseSearch(searchField.text)
        if (parsed.type === "all" && !parsed.needle) return root.allEntries

        const scored = []
        for (const line of root.allEntries) {
            const id      = clipEntry.entryId(line)
            const preview = clipEntry.entryPreview(line)
            const isImage = preview.startsWith("[[")

            if (parsed.type === "image" && !isImage) continue
            if (parsed.type === "text"  &&  isImage) continue
            if (!parsed.needle) { scored.push({ line, score: 0 }); continue }

            const fullText = root._fullTextCache[id]
            const haystack = (fullText || preview).toLowerCase().replace(/\s+/g, "")
            if (parsed.exact) {
                if (haystack.includes(parsed.needle)) scored.push({ line, score: 0 })
            } else {
                const score = fuzzy.fuzzyScore(parsed.needle, haystack)
                if (score >= 0) scored.push({ line, score })
            }
        }
        scored.sort((a, b) => b.score - a.score)
        return scored.map(s => s.line)
    }

    // ── Actions ──────────────────────────────────────────────────────────────
    function paste(rawLine) {
        pasteProcess.command = [
            bin.bash, "-c",
            "printf '%s\\n' \"$1\" | " + bin.cliphist + " decode | " + bin.wlCopy,
            "--", rawLine
        ]
        root.itemPasted(resultList.currentIndex)
        pasteProcess.running = true
        closeTimer.restart()
    }

    function enterInsertMode() {
        root.mode = "insert"
        searchField.forceActiveFocus()
    }

    function enterNormalMode() {
        root.mode = "normal"
        normalModeHandler.forceActiveFocus()
    }

    function navUp()       { if (resultList.currentIndex > 0) resultList.currentIndex-- }
    function navDown()     { if (resultList.currentIndex < resultList.count - 1) resultList.currentIndex++ }
    function navTop()      { resultList.currentIndex = 0 }
    function navBottom()   { resultList.currentIndex = Math.max(0, resultList.count - 1) }
    function navHalfDown() {
        const step = Math.max(1, Math.floor(resultList.height / 40 / 2))
        resultList.currentIndex = Math.min(resultList.count - 1, resultList.currentIndex + step)
    }
    function navHalfUp() {
        const step = Math.max(1, Math.floor(resultList.height / 40 / 2))
        resultList.currentIndex = Math.max(0, resultList.currentIndex - step)
    }

    // ── Processes ────────────────────────────────────────────────────────────
    Process {
        id: listProcess
        command: [bin.cliphist, "list"]
        stdout: SplitParser {
            onRead: (line) => { if (line !== "") root._buf.push(line) }
        }
        onExited: {
            root.allEntries = root._buf.slice()
            root._buf = []
            root._fullTextCache = {}
            root._cacheVersion = 0
            fullTextDecodeProcess.exec([bin.cliphistDecodeAll])
        }
    }

    Process {
        id: fullTextDecodeProcess
        stdout: SplitParser {
            onRead: (line) => {
                const tab = line.indexOf("\t")
                if (tab < 0) return
                const id = line.substring(0, tab)
                try {
                    root._fullTextCache[id] = JSON.parse(line.substring(tab + 1))
                    root._cacheVersion++
                } catch (_) {}
            }
        }
    }

    Process { id: pasteProcess }

    Timer {
        id: closeTimer
        interval: 200
        repeat: false
        onTriggered: root.showing = false
    }

    Timer {
        id: gTimer
        interval: 300
        repeat: false
        onTriggered: { root._pendingG = false }
    }

    // ── IPC ──────────────────────────────────────────────────────────────────
    IpcHandler {
        target: "viewer"
        readonly property bool   showing: root.showing
        readonly property string mode:    root.mode

        function toggle() { root.showing = !root.showing }

        function setMode(m: string) {
            if (m === "insert") root.enterInsertMode()
            else if (m === "normal") root.enterNormalMode()
        }

        function nav(dir: string) {
            if      (dir === "up")        root.navUp()
            else if (dir === "down")      root.navDown()
            else if (dir === "top")       root.navTop()
            else if (dir === "bottom")    root.navBottom()
            else if (dir === "half-down") root.navHalfDown()
            else if (dir === "half-up")   root.navHalfUp()
        }

        function key(k: string) {
            const lk = k.toLowerCase()
            if (lk === "escape" || lk === "esc") {
                if (root.mode === "insert") root.enterNormalMode()
                else root.showing = false
            } else if (lk === "enter" || lk === "return") {
                if (root.selectedEntry !== "") root.paste(root.selectedEntry)
            }
        }

        function type(text: string) {
            if (root.mode !== "insert") root.enterInsertMode()
            searchField.text += text
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
        namespace: "kh-cliphist"
        anchors { top: true; bottom: true; left: true; right: true }

        onVisibleChanged: {
            if (visible) {
                root.allEntries = []
                root._buf = []
                root._fullTextCache = {}
                root._cacheVersion = 0
                fullTextDecodeProcess.running = false
                searchField.text = ""
                resultList.currentIndex = 0
                root.enterInsertMode()
                if (!listProcess.running) listProcess.running = true
            }
        }

        // Backdrop ────────────────────────────────────────────────────────────
        Rectangle {
            anchors.fill: parent
            color: "#99000000"
            MouseArea { anchors.fill: parent; onClicked: root.showing = false }
        }

        // Panel ───────────────────────────────────────────────────────────────
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

            // Normal mode key handler — holds focus in normal mode
            Item {
                id: normalModeHandler
                anchors.fill: parent

                Keys.onPressed: (event) => {
                    if (event.key === Qt.Key_Shift || event.key === Qt.Key_Control ||
                        event.key === Qt.Key_Alt   || event.key === Qt.Key_Meta) return

                    if (event.key === Qt.Key_Escape) {
                        root.showing = false
                    } else if (event.key === Qt.Key_J || event.key === Qt.Key_Down) {
                        root.navDown()
                    } else if (event.key === Qt.Key_K || event.key === Qt.Key_Up) {
                        root.navUp()
                    } else if (event.key === Qt.Key_G && (event.modifiers & Qt.ShiftModifier)) {
                        root.navBottom()
                    } else if (event.key === Qt.Key_G) {
                        if (root._pendingG) {
                            gTimer.stop()
                            root.navTop()
                            root._pendingG = false
                        } else {
                            root._pendingG = true
                            gTimer.restart()
                        }
                    } else if (event.key === Qt.Key_D && (event.modifiers & Qt.ControlModifier)) {
                        root.navHalfDown()
                    } else if (event.key === Qt.Key_U && (event.modifiers & Qt.ControlModifier)) {
                        root.navHalfUp()
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        if (root.selectedEntry !== "") root.paste(root.selectedEntry)
                    } else if (event.key === Qt.Key_Slash) {
                        root.enterInsertMode()
                    } else if (event.text && event.text.length === 1 &&
                               event.text.charCodeAt(0) >= 32) {
                        root.enterInsertMode()
                        searchField.text += event.text
                    } else {
                        return
                    }
                    event.accepted = true
                }
            }

            Column {
                id: column
                x: 8; y: 8
                width: parent.width - 16
                spacing: 4

                // Search bar ──────────────────────────────────────────────────
                Rectangle {
                    id: searchBox
                    width: parent.width
                    height: 44
                    color: cfg.color.base01
                    radius: 8

                    Rectangle {
                        id: modeTag
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        visible: root.mode === "normal"
                        width: modeLabel.implicitWidth + 12
                        height: 22
                        radius: 4
                        color: cfg.color.base02

                        Text {
                            id: modeLabel
                            anchors.centerIn: parent
                            text: "NOR"
                            color: cfg.color.base0D
                            font.family: cfg.fontFamily
                            font.pixelSize: cfg.fontSize - 3
                            font.bold: true
                        }
                    }

                    TextInput {
                        id: searchField
                        anchors.fill: parent
                        anchors.leftMargin: root.mode === "normal" ? modeTag.width + 18 : 14
                        anchors.rightMargin: 14
                        color: cfg.color.base05
                        font.family: cfg.fontFamily
                        font.pixelSize: cfg.fontSize
                        clip: true
                        verticalAlignment: TextInput.AlignVCenter
                        readOnly: root.mode === "normal"

                        Text {
                            anchors.fill: parent
                            visible: !searchField.text
                            text: "Search clipboard..."
                            color: cfg.color.base03
                            font.family: cfg.fontFamily
                            font.pixelSize: cfg.fontSize
                            verticalAlignment: Text.AlignVCenter
                        }

                        onTextChanged: resultList.currentIndex = 0

                        Keys.onEscapePressed: root.enterNormalMode()
                    }
                }

                // Entry list ──────────────────────────────────────────────────
                ListView {
                    id: resultList
                    width: parent.width
                    height: panel.height - searchBox.height - footer.height
                            - column.spacing * 2 - 16
                    clip: true
                    currentIndex: 0
                    model: root.filteredEntries
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
                        height: isImage ? 64 : 40

                        readonly property bool   isCurrent: resultList.currentIndex === index
                        readonly property string preview:   clipEntry.entryPreview(modelData)
                        readonly property bool   isImage:   preview.startsWith("[[")
                        readonly property string entryId:   clipEntry.entryId(modelData)
                        readonly property string tmpPath:   "/tmp/kh-cliphist-" + entryId

                        Process {
                            id: imgDecode
                            command: [
                                bin.bash, "-c",
                                "[ -f \"$1\" ] || printf '%s\\n' \"$2\" | " + bin.cliphist + " decode > \"$1\"",
                                "--", delegateRoot.tmpPath, delegateRoot.modelData
                            ]
                            onExited: imgThumb.source = "file://" + delegateRoot.tmpPath
                        }
                        Component.onCompleted: { if (isImage) imgDecode.running = true }

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 2
                            color: delegateRoot.isCurrent ? cfg.color.base02 : "transparent"
                            radius: 6

                            Image {
                                id: imgThumb
                                visible: delegateRoot.isImage
                                width: 90
                                anchors { top: parent.top; bottom: parent.bottom; left: parent.left; margins: 4 }
                                fillMode: Image.PreserveAspectFit
                                smooth: true; mipmap: true; asynchronous: true
                            }

                            Text {
                                visible: !delegateRoot.isImage
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                text: delegateRoot.preview
                                color: cfg.color.base05
                                font.family: cfg.fontFamily
                                font.pixelSize: cfg.fontSize
                                verticalAlignment: Text.AlignVCenter
                                elide: Text.ElideRight
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
                                function onItemPasted(idx) {
                                    if (idx === delegateRoot.index) blinkAnim.restart()
                                }
                            }
                        }
                    }
                }

                // Footer ──────────────────────────────────────────────────────
                Item {
                    id: footer
                    width: parent.width
                    height: 28

                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.mode === "normal"
                            ? "j/k  navigate  \u00b7  Enter  paste  \u00b7  /  search  \u00b7  Esc  close"
                            : "Esc  normal mode"
                        color: cfg.color.base03
                        font.family: cfg.fontFamily
                        font.pixelSize: cfg.fontSize - 3
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        visible: root.filteredEntries.length > 0
                        text: (resultList.currentIndex + 1) + "/" + root.filteredEntries.length
                        color: cfg.color.base03
                        font.family: cfg.fontFamily
                        font.pixelSize: cfg.fontSize - 3
                    }
                }
            }
        }
    }
}
