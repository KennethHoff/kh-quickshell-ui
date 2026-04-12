// Clipboard history viewer.
//
// Daemon mode: quickshell -p <config-dir>
// Toggle:      quickshell ipc -c kh-cliphist call viewer toggle
//
// Keys (list):       Type to search · ↑↓ navigate · Enter paste · Tab → preview · Esc close
// Keys (detail):     ↑↓ scroll · Enter fullscreen · Tab → list · Esc → list
// Keys (fullscreen): ↑↓ scroll (text) · Esc / Enter / click → back to detail
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: root

    // ── Config (injected by Nix) ─────────────────────────────────────────────
    NixFFI        { id: cfg }
    FuzzyScore    { id: fuzzy }
    SearchParser  { id: searchParser }
    CliphistEntry { id: clipEntry }
    FormatBytes   { id: fmtBytes }

    // ── State ────────────────────────────────────────────────────────────────
    property bool   showing: false
    property string view: "list"   // "list" | "detail" | "help" | "fullscreen"
    property string helpFilter: ""
    property var    allEntries: []
    property var    _buf: []
    property var    _fullTextCache: ({})
    property int    _cacheVersion: 0
    signal itemPasted(int idx)

    readonly property string selectedEntry: {
        const entries = root.filteredEntries
        const idx = resultList.currentIndex
        if (idx >= 0 && idx < entries.length) return entries[idx]
        return ""
    }
    readonly property string selectedPreview: clipEntry.entryPreview(root.selectedEntry)
    readonly property bool   selectedIsImage: root.selectedPreview.startsWith("[[")
    readonly property string selectedEntryId: clipEntry.entryId(root.selectedEntry)

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
            cfg.bin.bash, "-c",
            "printf '%s\\n' \"$1\" | " + cfg.bin.cliphist + " decode | " + cfg.bin.wlCopy,
            "--", rawLine
        ]
        root.itemPasted(resultList.currentIndex)
        pasteProcess.running = true
        closeTimer.restart()
    }

    // ── Processes ────────────────────────────────────────────────────────────
    Process {
        id: listProcess
        command: [cfg.bin.cliphist, "list"]
        stdout: SplitParser {
            onRead: (line) => { if (line !== "") root._buf.push(line) }
        }
        onExited: {
            root.allEntries = root._buf.slice()
            root._buf = []
            root._fullTextCache = {}
            root._cacheVersion = 0
            fullTextDecodeProcess.exec([cfg.bin.cliphistDecodeAll])
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

    property int    detailImgFileSize: 0
    property string detailTextContent: ""

    Process {
        id: detailImgDecode
        property string targetPath: ""
        command: [
            cfg.bin.bash, "-c",
            "[ -f \"$1\" ] || printf '%s\\n' \"$2\" | " + cfg.bin.cliphist + " decode > \"$1\"",
            "--", targetPath, root.selectedEntry
        ]
        onExited: {
            detailImg.source = ""
            detailImg.source = "file://" + targetPath
            detailStatProcess.targetPath = targetPath
            detailStatProcess.running = true
        }
    }

    Process {
        id: detailStatProcess
        property string targetPath: ""
        property string _buf: ""
        command: [cfg.bin.stat, "--printf=%s", targetPath]
        stdout: SplitParser {
            onRead: (line) => { detailStatProcess._buf += line }
        }
        onExited: {
            root.detailImgFileSize = parseInt(detailStatProcess._buf) || 0
            detailStatProcess._buf = ""
        }
    }

    Process {
        id: detailTextProcess
        property string _buf: ""
        stdout: SplitParser {
            onRead: (line) => {
                detailTextProcess._buf += (detailTextProcess._buf ? "\n" : "") + line
            }
        }
        onExited: {
            root.detailTextContent = detailTextProcess._buf
            detailTextProcess._buf = ""
        }
    }

    onSelectedEntryIdChanged: {
        root.detailImgFileSize = 0
        root.detailTextContent = ""
        detailImgDecode.running = false
        detailStatProcess.running = false
        detailTextProcess.running = false
        if (root.selectedEntryId !== "") {
            if (root.selectedIsImage) {
                detailImgDecode.targetPath = "/tmp/kh-cliphist-detail-" + root.selectedEntryId
                detailImgDecode.exec(detailImgDecode.command)
            } else {
                detailTextProcess.exec([
                    cfg.bin.bash, "-c",
                    "printf '%s\\n' \"$1\" | " + cfg.bin.cliphist + " decode",
                    "--", root.selectedEntry
                ])
            }
        }
    }

    Timer {
        id: closeTimer
        interval: 200
        repeat: false
        onTriggered: root.showing = false
    }

    IpcHandler {
        target: "viewer"
        readonly property bool showing: root.showing
        function toggle() { root.showing = !root.showing }
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
                root.view = "list"
                searchField.text = ""
                searchField.forceActiveFocus()
                resultList.currentIndex = 0
                if (!listProcess.running) listProcess.running = true
            }
        }

        // Fullscreen overlay ─────────────────────────────────────────────────
        Rectangle {
            id: fullscreenOverlay
            anchors.fill: parent
            color: "#DD000000"
            visible: root.view === "fullscreen"
            z: 10

            MouseArea { anchors.fill: parent; onClicked: root.view = "detail" }

            Image {
                id: fullscreenImg
                visible: root.selectedIsImage
                anchors.fill: parent
                anchors.margins: 40
                source: detailImg.source
                fillMode: Image.PreserveAspectFit
                smooth: true; mipmap: true; asynchronous: true
            }

            Text {
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottomMargin: 16
                visible: fullscreenImg.visible && fullscreenImg.implicitWidth > 0
                text: fullscreenImg.implicitWidth + " \u00d7 " + fullscreenImg.implicitHeight + " px"
                color: cfg.color.base04
                font.family: cfg.fontFamily
                font.pixelSize: cfg.fontSize
            }

            Flickable {
                id: fullscreenFlickable
                visible: !root.selectedIsImage
                anchors.fill: parent
                anchors.margins: 40
                clip: true
                contentHeight: fullscreenText.implicitHeight
                flickableDirection: Flickable.VerticalFlick

                Text {
                    id: fullscreenText
                    width: parent.width
                    text: root.detailTextContent || root.selectedPreview
                    color: cfg.color.base05
                    font.family: cfg.fontFamily
                    font.pixelSize: cfg.fontSize
                    wrapMode: Text.Wrap
                }
            }

            Text {
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: 16
                text: "Esc or click to close"
                color: cfg.color.base03
                font.family: cfg.fontFamily
                font.pixelSize: cfg.fontSize - 3
            }
        }

        // Backdrop ───────────────────────────────────────────────────────────
        Rectangle {
            anchors.fill: parent
            color: "#99000000"
            MouseArea { anchors.fill: parent; onClicked: root.showing = false }
        }

        // Panel ──────────────────────────────────────────────────────────────
        Rectangle {
            id: panel
            width: parent.width * 0.7
            height: parent.height * 0.7
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: parent.height * 0.06
            color: cfg.color.base00
            radius: 12
            clip: true

            MouseArea { anchors.fill: parent }

            Column {
                id: column
                x: 8; y: 8
                width: parent.width - 16
                spacing: 4

                // Search box ─────────────────────────────────────────────────
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
                                : (root.view === "detail" ? "Preview" : "Search clipboard... (img: text:)")
                            color: (root.view === "help") && root.helpFilter
                                ? cfg.color.base05
                                : cfg.color.base03
                            font.family: cfg.fontFamily
                            font.pixelSize: cfg.fontSize
                            verticalAlignment: Text.AlignVCenter
                            visible: root.view !== "list" || !searchField.text
                        }

                        onTextChanged: resultList.currentIndex = 0

                        Keys.onEscapePressed: {
                            if (root.view === "help") {
                                if (root.helpFilter) root.helpFilter = ""
                                else root.view = "list"
                                return
                            }
                            if (root.view === "fullscreen") root.view = "detail"
                            else if (root.view === "detail") root.view = "list"
                            else root.showing = false
                        }
                        Keys.onReturnPressed: {
                            if (root.view === "help") return
                            if (root.view === "fullscreen") { root.view = "detail"; return }
                            if (root.view === "detail")     { root.view = "fullscreen"; return }
                            const entries = root.filteredEntries
                            if (resultList.currentIndex >= 0 && resultList.currentIndex < entries.length)
                                root.paste(entries[resultList.currentIndex])
                        }
                        Keys.onUpPressed: {
                            if (root.view === "help") return
                            if (root.view === "detail")
                                detailFlickable.contentY = Math.max(0, detailFlickable.contentY - 30)
                            else if (root.view === "list" && resultList.currentIndex > 0)
                                resultList.currentIndex--
                        }
                        Keys.onDownPressed: {
                            if (root.view === "help") return
                            if (root.view === "detail")
                                detailFlickable.contentY = Math.min(
                                    detailFlickable.contentHeight - detailFlickable.height,
                                    detailFlickable.contentY + 30)
                            else if (root.view === "list" && resultList.currentIndex < resultList.count - 1)
                                resultList.currentIndex++
                        }
                        Keys.onPressed: (event) => {
                            if (event.key === Qt.Key_Shift || event.key === Qt.Key_Control ||
                                event.key === Qt.Key_Alt  || event.key === Qt.Key_Meta) return
                            if (root.view === "fullscreen") {
                                if (event.key === Qt.Key_Escape) root.view = "detail"
                                else if (event.key === Qt.Key_Up && !root.selectedIsImage)
                                    fullscreenFlickable.contentY = Math.max(0, fullscreenFlickable.contentY - 30)
                                else if (event.key === Qt.Key_Down && !root.selectedIsImage)
                                    fullscreenFlickable.contentY = Math.min(
                                        fullscreenFlickable.contentHeight - fullscreenFlickable.height,
                                        fullscreenFlickable.contentY + 30)
                                event.accepted = true
                                return
                            }
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
                            }
                            if (event.key === Qt.Key_Tab) {
                                root.view = root.view === "list" ? "detail" : "list"
                                event.accepted = true
                            }
                        }
                    }
                }

                // Split view: list + detail ───────────────────────────────────
                RowLayout {
                    width: parent.width
                    height: panel.height - searchBox.height - footerHint.height - column.spacing * 2 - 16
                    visible: root.view !== "help"
                    spacing: 4

                    // Entry list (left) ───────────────────────────────────────
                    Item {
                        Layout.preferredWidth: parent.width * 0.45
                        Layout.fillHeight: true

                        ListView {
                            id: resultList
                            anchors.fill: parent
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
                                height: delegateRoot.isImage ? 64 : 40

                                readonly property bool   isCurrent: resultList.currentIndex === index
                                readonly property string preview:   clipEntry.entryPreview(modelData)
                                readonly property bool   isImage:   preview.startsWith("[[")
                                readonly property string entryId:   clipEntry.entryId(modelData)
                                readonly property string tmpPath:   "/tmp/kh-cliphist-" + entryId

                                Process {
                                    id: imgDecode
                                    command: [
                                        cfg.bin.bash, "-c",
                                        "[ -f \"$1\" ] || printf '%s\\n' \"$2\" | " + cfg.bin.cliphist + " decode > \"$1\"",
                                        "--", delegateRoot.tmpPath, delegateRoot.modelData
                                    ]
                                    onExited: { imgThumb.source = "file://" + delegateRoot.tmpPath }
                                }
                                Component.onCompleted: { if (isImage) imgDecode.running = true }

                                Rectangle {
                                    anchors.fill: parent
                                    anchors.margins: 2
                                    color: delegateRoot.isCurrent
                                        ? cfg.color.base02
                                        : (hoverArea.containsMouse ? cfg.color.base01 : "transparent")
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

                                    MouseArea {
                                        id: hoverArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onClicked: {
                                            resultList.currentIndex = delegateRoot.index
                                            root.paste(delegateRoot.modelData)
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
                                        function onItemPasted(idx) { if (idx === delegateRoot.index) blinkAnim.restart() }
                                    }
                                }
                            }
                        }

                        Text {
                            anchors { bottom: parent.bottom; right: parent.right; margins: 4 }
                            visible: root.filteredEntries.length > 0
                            text: (resultList.currentIndex + 1) + "/" + root.filteredEntries.length
                            color: cfg.color.base03
                            font.family: cfg.fontFamily
                            font.pixelSize: cfg.fontSize - 3
                        }
                    }

                    // Separator ───────────────────────────────────────────────
                    Rectangle {
                        Layout.preferredWidth: 1
                        Layout.fillHeight: true
                        color: cfg.color.base02
                    }

                    // Detail panel (right) ─────────────────────────────────────
                    Rectangle {
                        id: detailPanel
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        color: "transparent"
                        border.width: root.view === "detail" ? 1 : 0
                        border.color: cfg.color.base02
                        radius: 6

                        Text {
                            anchors.centerIn: parent
                            visible: root.selectedEntry === ""
                            text: "No selection"
                            color: cfg.color.base03
                            font.family: cfg.fontFamily
                            font.pixelSize: cfg.fontSize
                        }

                        Column {
                            anchors { fill: parent; margins: 10 }
                            spacing: 8
                            visible: root.selectedEntry !== "" && !root.selectedIsImage

                            Flickable {
                                id: detailFlickable
                                width: parent.width
                                height: parent.height - detailStats.height - parent.spacing
                                clip: true
                                contentHeight: detailText.implicitHeight
                                flickableDirection: Flickable.VerticalFlick

                                Text {
                                    id: detailText
                                    width: parent.width
                                    text: root.detailTextContent || root.selectedPreview
                                    color: cfg.color.base05
                                    font.family: cfg.fontFamily
                                    font.pixelSize: cfg.fontSize - 1
                                    wrapMode: Text.Wrap
                                }
                            }

                            Text {
                                id: detailStats
                                width: parent.width
                                readonly property string preview: root.detailTextContent || root.selectedPreview
                                readonly property int charCount: preview.length
                                readonly property int wordCount: preview.trim() === "" ? 0 : preview.trim().split(/\s+/).length
                                readonly property int lineCount: preview.split("\n").length
                                text: {
                                    const parts = [
                                        charCount + " chars",
                                        wordCount + " words",
                                        lineCount + (lineCount === 1 ? " line" : " lines"),
                                    ]
                                    if (root.view === "detail") parts.push("Enter to fullscreen")
                                    return parts.join("  \u00b7  ")
                                }
                                color: cfg.color.base03
                                font.family: cfg.fontFamily
                                font.pixelSize: cfg.fontSize - 3
                            }
                        }

                        Column {
                            anchors { fill: parent; margins: 10 }
                            spacing: 8
                            visible: root.selectedEntry !== "" && root.selectedIsImage

                            Image {
                                id: detailImg
                                width: parent.width
                                height: parent.height - imgStats.height - parent.spacing
                                fillMode: Image.PreserveAspectFit
                                smooth: true; mipmap: true; asynchronous: true
                            }

                            Text {
                                id: imgStats
                                width: parent.width
                                text: {
                                    const parts = []
                                    if (detailImg.implicitWidth > 0)
                                        parts.push(detailImg.implicitWidth + " \u00d7 " + detailImg.implicitHeight + " px")
                                    if (root.detailImgFileSize > 0)
                                        parts.push(fmtBytes.formatBytes(root.detailImgFileSize))
                                    if (root.view === "detail")
                                        parts.push("Enter to fullscreen")
                                    return parts.join("  \u00b7  ")
                                }
                                color: cfg.color.base03
                                font.family: cfg.fontFamily
                                font.pixelSize: cfg.fontSize - 3
                            }
                        }
                    }
                }

                // Help overlay ───────────────────────────────────────────────
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

                    SectionLabel { text: "List" }
                    ShortcutRow { shortcut: "\u2191 / \u2193"; description: "Navigate" }
                    ShortcutRow { shortcut: "Enter";          description: "Paste" }
                    ShortcutRow { shortcut: "Tab";            description: "Switch to preview" }
                    ShortcutRow { shortcut: "Esc";            description: "Close" }
                    ShortcutRow { shortcut: "?";              description: "Toggle this help" }

                    SectionLabel { text: "Search filters" }
                    ShortcutRow { shortcut: "img:";  description: "Images only" }
                    ShortcutRow { shortcut: "text:"; description: "Text only" }
                    ShortcutRow { shortcut: "'";     description: "Exact substring match" }

                    SectionLabel { text: "Preview" }
                    ShortcutRow { shortcut: "\u2191 / \u2193"; description: "Scroll" }
                    ShortcutRow { shortcut: "Enter";           description: "Fullscreen" }
                    ShortcutRow { shortcut: "Tab / Esc";       description: "Back to list" }

                    Item { width: 1; height: 4 }
                }

                // Footer hint ────────────────────────────────────────────────
                Item {
                    id: footerHint
                    width: parent.width
                    height: 28
                    visible: root.view !== "help"
                    Text {
                        anchors.centerIn: parent
                        text: root.view === "detail"
                            ? "Tab  list  \u00b7  Esc  back  \u00b7  ?  help"
                            : "Tab  preview  \u00b7  ?  help"
                        color: cfg.color.base03
                        font.family: cfg.fontFamily
                        font.pixelSize: cfg.fontSize - 3
                    }
                }
            }
        }
    }
}
