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
    HelpFilter    { id: helpFilter }

    // ── State ────────────────────────────────────────────────────────────────
    property bool   showing: false
    property string mode: "insert"      // "insert" | "normal"
    property bool   helpShowing: false
    property string helpText: ""        // help filter text
    property bool   _helpFiltering: false
    property var    allEntries: []
    property var    filteredEntries: []
    property var    _buf: []
    property var    _processed: []       // [{line, isImage, haystack}] — parallel to allEntries
    property var    _processedIdx: ({})  // id → index in _processed for O(1) full-text updates
    property bool   _pendingG: false

    property bool   detailFocused: false
    property bool   _detailIsImage: false
    property string _detailText: ""
    property var    _detailLines: []
    property bool   _detailLoading: false
    property string _detailImgPath: ""
    property string _detailImgSource: ""
    property string _detailImgSize: ""

    signal itemPasted(int idx)

    readonly property string selectedEntry: {
        const idx = resultList.currentIndex
        const entries = root.filteredEntries
        return (idx >= 0 && idx < entries.length) ? entries[idx] : ""
    }
    onSelectedEntryChanged: detailRefreshTimer.restart()

    // ── Filtering ────────────────────────────────────────────────────────────
    function _runFilter() {
        const parsed = searchParser.parseSearch(searchField.text)
        if (parsed.type === "all" && !parsed.needle) {
            root.filteredEntries = root.allEntries
            return
        }
        const scored = []
        for (const e of root._processed) {
            if (parsed.type === "image" && !e.isImage) continue
            if (parsed.type === "text"  &&  e.isImage) continue
            if (!parsed.needle) { scored.push({ line: e.line, score: 0 }); continue }
            if (parsed.exact) {
                if (e.haystack.includes(parsed.needle)) scored.push({ line: e.line, score: 0 })
            } else {
                const score = fuzzy.fuzzyScore(parsed.needle, e.haystack)
                if (score >= 0) scored.push({ line: e.line, score })
            }
        }
        scored.sort((a, b) => b.score - a.score)
        root.filteredEntries = scored.map(s => s.line)
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

    function yank(rawLine) {
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

    function openHelp() {
        root.helpShowing = true
        root._helpFiltering = false
        root.helpText = ""
        helpFlick.contentY = 0
        normalModeHandler.forceActiveFocus()
    }

    function closeHelp() {
        root.helpShowing = false
        root._helpFiltering = false
        root.helpText = ""
        if (root.mode === "insert") root.enterInsertMode()
        else normalModeHandler.forceActiveFocus()
    }

    function _refreshDetail() {
        if (root.selectedEntry === "") {
            root._detailText    = ""
            root._detailLines   = []
            root._detailLoading = false
            root._detailImgSource = ""
            root._detailImgSize = ""
            return
        }
        const preview = clipEntry.entryPreview(root.selectedEntry)
        root._detailIsImage  = preview.startsWith("[[")
        root._detailText     = ""
        root._detailLines    = []
        root._detailLoading  = true
        root._detailImgSource = ""
        root._detailImgSize  = ""
        const eid = clipEntry.entryId(root.selectedEntry)
        root._detailImgPath  = "/tmp/kh-cliphist-" + eid
        detailFlick.contentY = 0
        if (root._detailIsImage) {
            detailDecodeProcess.command = [
                bin.bash, "-c",
                "[ -f \"$1\" ] || printf '%s\\n' \"$2\" | " + bin.cliphist + " decode > \"$1\"",
                "--", root._detailImgPath, root.selectedEntry
            ]
        } else {
            detailDecodeProcess.command = [
                bin.bash, "-c",
                "printf '%s\\n' \"$1\" | " + bin.cliphist + " decode",
                "--", root.selectedEntry
            ]
        }
        detailDecodeProcess.running = true
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

            const processed = [], idx = {}
            for (let i = 0; i < root.allEntries.length; i++) {
                const line = root.allEntries[i]
                const tab  = line.indexOf("\t")
                const id      = tab >= 0 ? line.substring(0, tab) : line
                const preview = tab >= 0 ? line.substring(tab + 1) : line
                const isImage = preview.startsWith("[[")
                processed.push({ line, isImage, haystack: isImage ? "" : preview.toLowerCase().replace(/\s+/g, "") })
                idx[id] = i
            }
            root._processed    = processed
            root._processedIdx = idx

            root._runFilter()
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
                    const fullText = JSON.parse(line.substring(tab + 1))
                    const i = root._processedIdx[id]
                    if (i !== undefined)
                        root._processed[i].haystack = fullText.toLowerCase().replace(/\s+/g, "")
                    searchDebounce.restart()
                } catch (_) {}
            }
        }
    }

    Process { id: pasteProcess }

    Process {
        id: detailDecodeProcess
        stdout: SplitParser {
            onRead: (line) => { if (!root._detailIsImage) root._detailLines.push(line) }
        }
        onExited: {
            if (root._detailIsImage) {
                root._detailImgSource = "file://" + root._detailImgPath
                detailSizeProcess.command = [
                    bin.bash, "-c", "wc -c < \"$1\"", "--", root._detailImgPath
                ]
                detailSizeProcess.running = true
            } else {
                root._detailText  = root._detailLines.join("\n")
                root._detailLines = []
                root._detailLoading = false
            }
        }
    }

    Process {
        id: detailSizeProcess
        stdout: SplitParser {
            onRead: (line) => {
                const bytes = parseInt(line.trim())
                if (isNaN(bytes)) return
                if (bytes < 1024)    root._detailImgSize = bytes + " B"
                else if (bytes < 1048576) root._detailImgSize = (bytes / 1024).toFixed(1) + " KB"
                else                 root._detailImgSize = (bytes / 1048576).toFixed(1) + " MB"
            }
        }
    }

    Timer {
        id: closeTimer
        interval: 200
        repeat: false
        onTriggered: root.showing = false
    }

    Timer {
        id: searchDebounce
        interval: 80
        repeat: false
        onTriggered: root._runFilter()
    }

    Timer {
        id: gTimer
        interval: 300
        repeat: false
        onTriggered: { root._pendingG = false }
    }

    Timer {
        id: detailRefreshTimer
        interval: 120
        repeat: false
        onTriggered: root._refreshDetail()
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

        function setView(v: string) {
            if (v === "help") root.openHelp()
            else if (v === "list") root.closeHelp()
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
            if (lk === "?") {
                root.helpShowing ? root.closeHelp() : root.openHelp()
            } else if (lk === "/" && root.helpShowing) {
                root._helpFiltering = true
                root.helpText = ""
            } else if (lk === "l" && !root.helpShowing) {
                root.detailFocused = true
            } else if (lk === "h" && root.detailFocused) {
                root.detailFocused = false
            } else if (lk === "escape" || lk === "esc") {
                if (root.helpShowing) {
                    if (root.helpText) { root.helpText = ""; root._helpFiltering = false }
                    else root.closeHelp()
                } else if (root.detailFocused) {
                    root.detailFocused = false
                } else if (root.mode === "insert") {
                    root.enterNormalMode()
                } else {
                    root.showing = false
                }
            } else if (lk === "y") {
                if (root.selectedEntry !== "") root.yank(root.selectedEntry)
            }
        }

        function type(text: string) {
            if (root.helpShowing) {
                root._helpFiltering = true
                root.helpText += text
            } else if (root.mode === "insert") {
                searchField.text += text
                searchDebounce.stop()
                root._runFilter()
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
        namespace: "kh-cliphist"
        anchors { top: true; bottom: true; left: true; right: true }

        onVisibleChanged: {
            if (visible) {
                root.allEntries      = []
                root.filteredEntries = []
                root._buf            = []
                root._processed      = []
                root._processedIdx   = {}
                root.helpShowing     = false
                root._helpFiltering  = false
                root.helpText        = ""
                root.detailFocused   = false
                root._detailText     = ""
                root._detailLines    = []
                root._detailLoading  = false
                root._detailImgSource = ""
                detailRefreshTimer.stop()
                searchDebounce.stop()
                fullTextDecodeProcess.running = false
                searchField.text = ""
                resultList.currentIndex = 0
                root.enterNormalMode()
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

                    // ── Help popup ────────────────────────────────────────────
                    if (root.helpShowing) {
                        if (root._helpFiltering) {
                            if (event.key === Qt.Key_Escape) {
                                root.helpText = ""
                                root._helpFiltering = false
                            } else if (event.key === Qt.Key_Backspace) {
                                root.helpText = helpFilter.applyBackspace(root.helpText)
                            } else if (event.key === Qt.Key_W && (event.modifiers & Qt.ControlModifier)) {
                                root.helpText = helpFilter.applyCtrlW(root.helpText)
                            } else if (event.key === Qt.Key_U && (event.modifiers & Qt.ControlModifier)) {
                                root.helpText = ""
                            } else if (event.text && event.text.length === 1 &&
                                       event.text.charCodeAt(0) >= 32) {
                                root.helpText += event.text
                            } else {
                                return
                            }
                        } else {
                            const rowH = 30
                            const halfPage = Math.max(rowH, Math.floor(helpFlick.height / 2))
                            if (event.key === Qt.Key_Escape || event.text === "?") {
                                root.closeHelp()
                            } else if (event.key === Qt.Key_Slash) {
                                root._helpFiltering = true
                                root.helpText = ""
                            } else if (event.key === Qt.Key_J || event.key === Qt.Key_Down) {
                                helpFlick.contentY = Math.min(
                                    Math.max(0, helpFlick.contentHeight - helpFlick.height),
                                    helpFlick.contentY + rowH)
                            } else if (event.key === Qt.Key_K || event.key === Qt.Key_Up) {
                                helpFlick.contentY = Math.max(0, helpFlick.contentY - rowH)
                            } else if (event.key === Qt.Key_D && (event.modifiers & Qt.ControlModifier)) {
                                helpFlick.contentY = Math.min(
                                    Math.max(0, helpFlick.contentHeight - helpFlick.height),
                                    helpFlick.contentY + halfPage)
                            } else if (event.key === Qt.Key_U && (event.modifiers & Qt.ControlModifier)) {
                                helpFlick.contentY = Math.max(0, helpFlick.contentY - halfPage)
                            } else if (event.key === Qt.Key_G && (event.modifiers & Qt.ShiftModifier)) {
                                helpFlick.contentY = Math.max(0, helpFlick.contentHeight - helpFlick.height)
                            } else if (event.key === Qt.Key_G) {
                                helpFlick.contentY = 0
                            } else {
                                return
                            }
                        }
                        event.accepted = true
                        return
                    }

                    // ── Detail focus ──────────────────────────────────────────
                    if (root.detailFocused) {
                        const lineH = cfg.fontSize + 6
                        const halfPg = Math.max(lineH, Math.floor(detailFlick.height / 2))
                        if (event.key === Qt.Key_H || event.key === Qt.Key_Escape) {
                            root.detailFocused = false
                        } else if (event.text === "y") {
                            if (root.selectedEntry !== "") root.yank(root.selectedEntry)
                        } else if (!root._detailIsImage && (event.key === Qt.Key_J || event.key === Qt.Key_Down)) {
                            detailFlick.contentY = Math.min(
                                Math.max(0, detailFlick.contentHeight - detailFlick.height),
                                detailFlick.contentY + lineH)
                        } else if (!root._detailIsImage && (event.key === Qt.Key_K || event.key === Qt.Key_Up)) {
                            detailFlick.contentY = Math.max(0, detailFlick.contentY - lineH)
                        } else if (!root._detailIsImage && event.key === Qt.Key_D && (event.modifiers & Qt.ControlModifier)) {
                            detailFlick.contentY = Math.min(
                                Math.max(0, detailFlick.contentHeight - detailFlick.height),
                                detailFlick.contentY + halfPg)
                        } else if (!root._detailIsImage && event.key === Qt.Key_U && (event.modifiers & Qt.ControlModifier)) {
                            detailFlick.contentY = Math.max(0, detailFlick.contentY - halfPg)
                        } else if (!root._detailIsImage && event.key === Qt.Key_G && (event.modifiers & Qt.ShiftModifier)) {
                            detailFlick.contentY = Math.max(0, detailFlick.contentHeight - detailFlick.height)
                        } else if (!root._detailIsImage && event.key === Qt.Key_G) {
                            detailFlick.contentY = 0
                        } else {
                            return
                        }
                        event.accepted = true
                        return
                    }

                    // ── List ──────────────────────────────────────────────────
                    if (event.key === Qt.Key_Escape) {
                        root.showing = false
                    } else if (event.text === "?") {
                        root.openHelp()
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
                    } else if (event.text === "y") {
                        if (root.selectedEntry !== "") root.yank(root.selectedEntry)
                    } else if (event.key === Qt.Key_L) {
                        root.detailFocused = true
                    } else if (event.key === Qt.Key_Slash) {
                        root.enterInsertMode()
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

                        onTextChanged: { resultList.currentIndex = 0; searchDebounce.restart() }

                        Keys.onEscapePressed: root.enterNormalMode()

                        Keys.onPressed: (event) => {
                            if (!(event.modifiers & Qt.ControlModifier)) return
                            const pos = searchField.cursorPosition
                            const len = searchField.text.length
                            if (event.key === Qt.Key_A) {
                                searchField.cursorPosition = 0
                            } else if (event.key === Qt.Key_E) {
                                searchField.cursorPosition = len
                            } else if (event.key === Qt.Key_F) {
                                searchField.cursorPosition = Math.min(len, pos + 1)
                            } else if (event.key === Qt.Key_B) {
                                searchField.cursorPosition = Math.max(0, pos - 1)
                            } else if (event.key === Qt.Key_D) {
                                if (pos < len) searchField.remove(pos, pos + 1)
                            } else if (event.key === Qt.Key_K) {
                                if (pos < len) searchField.remove(pos, len)
                            } else if (event.key === Qt.Key_W) {
                                let i = pos
                                while (i > 0 && searchField.text[i - 1] === " ") i--
                                while (i > 0 && searchField.text[i - 1] !== " ") i--
                                if (i !== pos) searchField.remove(i, pos)
                            } else if (event.key === Qt.Key_U) {
                                if (pos > 0) searchField.remove(0, pos)
                            } else {
                                return
                            }
                            event.accepted = true
                        }
                    }
                }

                // Content area (list + detail side-by-side) ──────────────────
                Item {
                    id: contentArea
                    width: parent.width
                    height: panel.height - searchBox.height - footer.height
                            - column.spacing * 2 - 16

                    // Entry list
                    ListView {
                        id: resultList
                        width: Math.round(parent.width * 0.4)
                        height: parent.height
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

                    // Divider (highlights when detail is focused)
                    Rectangle {
                        x: resultList.width
                        width: 1
                        height: parent.height
                        color: root.detailFocused ? cfg.color.base0D : cfg.color.base02
                    }

                    // Detail panel
                    Item {
                        id: detailPanel
                        x: resultList.width + 1
                        width: parent.width - resultList.width - 1
                        height: parent.height

                        // Header: type badge + preview
                        Item {
                            id: detailHeader
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            height: 36

                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                text: root._detailIsImage ? "IMAGE" : "TEXT"
                                color: cfg.color.base0D
                                font.family: cfg.fontFamily
                                font.pixelSize: cfg.fontSize - 3
                                font.bold: true
                                font.letterSpacing: 1
                            }
                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: 68
                                anchors.right: parent.right
                                anchors.rightMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.selectedEntry !== "" ? clipEntry.entryPreview(root.selectedEntry) : ""
                                color: cfg.color.base03
                                font.family: cfg.fontFamily
                                font.pixelSize: cfg.fontSize - 3
                                elide: Text.ElideRight
                            }
                            Rectangle {
                                anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                                height: 1; color: cfg.color.base02
                            }
                        }

                        // Stats bar
                        Item {
                            id: detailStatsBar
                            anchors.bottom: parent.bottom
                            anchors.left: parent.left
                            anchors.right: parent.right
                            height: 28

                            Rectangle {
                                anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                                height: 1; color: cfg.color.base02
                            }
                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                color: cfg.color.base03
                                font.family: cfg.fontFamily
                                font.pixelSize: cfg.fontSize - 3
                                text: {
                                    if (root._detailLoading) return ""
                                    if (root._detailIsImage) {
                                        const dim = detailImg.status === Image.Ready
                                            ? detailImg.implicitWidth + " \u00d7 " + detailImg.implicitHeight + " px"
                                            : ""
                                        return dim + (dim && root._detailImgSize ? "  \u00b7  " : "") + root._detailImgSize
                                    }
                                    const t = root._detailText
                                    const chars = t.length
                                    const words = t.trim() ? t.trim().split(/\s+/).length : 0
                                    const lines = t ? t.split("\n").length : 0
                                    return chars + " chars  \u00b7  " + words + " words  \u00b7  " + lines + " lines"
                                }
                            }
                        }

                        // Content area
                        Item {
                            anchors.top: detailHeader.bottom
                            anchors.bottom: detailStatsBar.top
                            anchors.left: parent.left
                            anchors.right: parent.right

                            Text {
                                anchors.centerIn: parent
                                visible: root._detailLoading
                                text: "Loading..."
                                color: cfg.color.base03
                                font.family: cfg.fontFamily
                                font.pixelSize: cfg.fontSize
                            }

                            Flickable {
                                id: detailFlick
                                anchors.fill: parent
                                visible: !root._detailIsImage && !root._detailLoading
                                contentHeight: detailTextContent.implicitHeight
                                contentWidth: width
                                clip: true

                                Text {
                                    id: detailTextContent
                                    width: parent.width
                                    leftPadding: 12; rightPadding: 12; topPadding: 10; bottomPadding: 10
                                    text: root._detailText
                                    color: cfg.color.base05
                                    font.family: cfg.fontFamily
                                    font.pixelSize: cfg.fontSize
                                    wrapMode: Text.Wrap
                                }
                            }

                            Image {
                                id: detailImg
                                anchors.fill: parent
                                anchors.margins: 10
                                visible: root._detailIsImage && !root._detailLoading
                                fillMode: Image.PreserveAspectFit
                                smooth: true; mipmap: true; asynchronous: true
                                source: root._detailImgSource
                                onStatusChanged: if (status === Image.Ready) root._detailLoading = false
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
                        text: root.detailFocused
                            ? "h / Esc  list  \u00b7  j/k  scroll  \u00b7  y  copy"
                            : root.mode === "normal"
                                ? "j/k  navigate  \u00b7  y  copy  \u00b7  l  detail  \u00b7  /  search  \u00b7  ?  help  \u00b7  Esc  close"
                                : "Esc  normal mode  \u00b7  ?  help"
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

            // Help popup backdrop ─────────────────────────────────────────────
            Rectangle {
                anchors.fill: parent
                visible: root.helpShowing
                color: "#88000000"
                z: 9
                radius: panel.radius
                MouseArea { anchors.fill: parent; onClicked: root.closeHelp() }
            }

            // Help popup ──────────────────────────────────────────────────────
            Rectangle {
                id: helpPopup
                visible: root.helpShowing
                z: 10
                width: Math.min(panel.width - 80, 400)
                anchors.centerIn: parent
                color: cfg.color.base01
                radius: 10
                height: helpPopupCol.implicitHeight

                Column {
                    id: helpPopupCol
                    width: parent.width

                    // Title bar
                    Rectangle {
                        width: parent.width
                        height: 38
                        color: cfg.color.base02
                        radius: helpPopup.radius
                        // Square off bottom corners
                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            height: helpPopup.radius
                            color: parent.color
                        }

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.mode === "insert" ? "INSERT MODE" : "NORMAL MODE"
                            color: cfg.color.base0D
                            font.family: cfg.fontFamily
                            font.pixelSize: cfg.fontSize - 3
                            font.bold: true
                            font.letterSpacing: 1
                        }
                    }

                    // Keybind rows (scrollable)
                    Flickable {
                        id: helpFlick
                        width: parent.width
                        height: Math.min(helpRows.implicitHeight, panel.height * 0.55)
                        contentWidth: width
                        contentHeight: helpRows.implicitHeight
                        clip: true

                        Column {
                            id: helpRows
                            width: helpFlick.width

                            component ShortcutRow: Item {
                                id: srow
                                required property string keys
                                required property string action
                                visible: helpFilter.rowMatches(root.helpText, keys, action)
                                width: helpRows.width
                                implicitHeight: visible ? 30 : 0
                                height: implicitHeight

                                Text {
                                    x: 16; width: 130
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: srow.keys
                                    color: cfg.color.base0D
                                    font.family: cfg.fontFamily
                                    font.pixelSize: cfg.fontSize
                                }
                                Text {
                                    x: 154
                                    anchors.right: parent.right
                                    anchors.rightMargin: 16
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: srow.action
                                    color: cfg.color.base05
                                    font.family: cfg.fontFamily
                                    font.pixelSize: cfg.fontSize
                                    elide: Text.ElideRight
                                }
                            }

                            // Insert-mode bindings
                            Item {
                                visible: root.mode === "insert"
                                width: helpRows.width
                                implicitHeight: visible ? insertCol.implicitHeight : 0
                                height: implicitHeight
                                Column {
                                    id: insertCol
                                    width: parent.width
                                    topPadding: 6
                                    bottomPadding: 6
                                    ShortcutRow { keys: "Esc";    action: "normal mode" }
                                    ShortcutRow { keys: "Ctrl+A"; action: "cursor to start" }
                                    ShortcutRow { keys: "Ctrl+E"; action: "cursor to end" }
                                    ShortcutRow { keys: "Ctrl+F"; action: "cursor forward" }
                                    ShortcutRow { keys: "Ctrl+B"; action: "cursor back" }
                                    ShortcutRow { keys: "Ctrl+D"; action: "delete char forward" }
                                    ShortcutRow { keys: "Ctrl+K"; action: "delete to end of line" }
                                    ShortcutRow { keys: "Ctrl+W"; action: "delete word back" }
                                    ShortcutRow { keys: "Ctrl+U"; action: "delete to line start" }
                                }
                            }

                            // Normal-mode bindings
                            Item {
                                visible: root.mode === "normal"
                                width: helpRows.width
                                implicitHeight: visible ? normalCol.implicitHeight : 0
                                height: implicitHeight
                                Column {
                                    id: normalCol
                                    width: parent.width
                                    topPadding: 6
                                    bottomPadding: 6
                                    ShortcutRow { keys: "j / ↓";  action: "down" }
                                    ShortcutRow { keys: "k / ↑";  action: "up" }
                                    ShortcutRow { keys: "gg";     action: "jump to top" }
                                    ShortcutRow { keys: "G";      action: "jump to bottom" }
                                    ShortcutRow { keys: "Ctrl+D"; action: "half-page down" }
                                    ShortcutRow { keys: "Ctrl+U"; action: "half-page up" }
                                    ShortcutRow { keys: "y";      action: "copy to clipboard" }
                                    ShortcutRow { keys: "l";      action: "focus detail pane" }
                                    ShortcutRow { keys: "h / Esc"; action: "focus list" }
                                    ShortcutRow { keys: "/";      action: "focus search" }
                                    ShortcutRow { keys: "Esc";    action: "close" }
                                }
                            }
                        }
                    }

                    // Filter bar
                    Rectangle {
                        width: parent.width
                        height: 36
                        color: cfg.color.base02
                        radius: helpPopup.radius
                        // Square off top corners
                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            height: helpPopup.radius
                            color: parent.color
                        }

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            text: root._helpFiltering
                                  ? (root.helpText || "")
                                  : "/  filter  \u00b7  ?  close"
                            color: (root._helpFiltering && root.helpText)
                                   ? cfg.color.base05 : cfg.color.base03
                            font.family: cfg.fontFamily
                            font.pixelSize: cfg.fontSize - 3
                        }
                    }
                }
            }
        }
    }
}
