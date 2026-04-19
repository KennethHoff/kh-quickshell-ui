// Standalone fullscreen text / image viewer — supports N files side-by-side.
//
// Usage (via wrapper): nix run .#kh-view -- <file-or-dir> [<file-or-dir2> ...]
//                      nix run .#kh-view -- --browse-history
//                      nix run .#kh-view -- --recall [N]
//                      nix run .#kh-view -- --list-history
//
// Directory args are expanded by the wrapper to their image files.
//
// Direct (Quickshell): KH_VIEW_LIST=/path/to/list quickshell -p <config-dir>
//   where the list file contains one TSV line per pane (path\tlabel\tdesc).
//   Set KH_VIEW_MODE=browse to open the history picker instead of loading
//   a list; combine with KH_VIEW_RECALL_INDEX=<N> to auto-select the
//   Nth-from-newest entry at launch (the wrapper's --recall does this).
//   Gallery history is read via MetaStore from
//   $XDG_DATA_HOME/kh-view/meta/history (see `listHistory` / `recall` IPC).
//
// Split mode (default): Tab cycles focus between panes.
// Fullscreen mode (f):  h/l steps through files one at a time.
// Both modes:           hjkl/Ctrl+D/U scroll; v/V/Ctrl+V visual; y yank; q/Esc quit.
// History browser:      j/k navigate, / focus search, Enter opens, Esc quits.
//                       Selecting an entry enters session view with a
//                       "Back to History" pill top-left; Esc returns to
//                       the browser instead of quitting.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "./lib"

ShellRoot {
    id: root

    NixConfig { id: cfg }
    NixBins   { id: bin }

    // ── Mode state ────────────────────────────────────────────────────────────
    // _mode toggles the top-level view between the session panes and the
    // history picker.  _cameFromBrowser records whether the current session
    // view was entered via the browser (so Esc returns there).
    property string _mode:              Quickshell.env("KH_VIEW_MODE") === "browse" ? "browser" : "session"
    property bool   _cameFromBrowser:   false
    readonly property int _autoRecallIdx: {
        const v = parseInt(Quickshell.env("KH_VIEW_RECALL_INDEX") || "0", 10)
        return isFinite(v) ? v : 0
    }

    // ── Session state ─────────────────────────────────────────────────────────
    property var  _panes:       []
    property var  _listItems:   []
    property bool _ready:       false
    property int  _focusedPane: 0
    property bool _fullscreen:  false
    property bool _wrap:        true

    // ── Picker state ──────────────────────────────────────────────────────────
    property string _pickerSearch: ""
    property string _pickerMode:   "insert"   // "insert" | "normal"

    // Filtered history rows, newest first. Each row: { ts, items }.
    readonly property var _pickerFiltered: {
        const q = _pickerSearch.trim().toLowerCase()
        const rows = functionality._sortedHistory().slice().reverse()  // newest first
        if (!q) return rows
        return rows.filter(r => {
            const first = r.items[0] || {}
            const hay = ((first.label || "") + " " + (first.path || "")).toLowerCase()
            return hay.includes(q)
        })
    }
    readonly property int _pickerCount: _pickerFiltered.length

    Component.onCompleted: functionality.init()

    // ── Read path list from KH_VIEW_LIST ──────────────────────────────────────
    Process {
        id: listProcess
        command: [bin.bash, "-c", "cat -- \"$KH_VIEW_LIST\""]
        stdout: SplitParser {
            onRead: (line) => functionality.onListRead(line)
        }
        onExited: functionality.onListExited()
    }

    // ── Gallery history (MetaStore-backed) ────────────────────────────────────
    // Rows are <epoch>\t<compact JSON items array>; the wrapper appends on
    // every normal launch.  We only read here — mutation lives in the wrapper
    // so history survives a crashed or accidentally-closed window.
    MetaStore {
        id: historyStore
        bash:     bin.bash
        appName:  "kh-view"
        storeKey: "history"
        onLoaded: functionality.onHistoryLoaded()
    }

    // ── Functionality ─────────────────────────────────────────────────────────
    QtObject {
        id: functionality

        // ui+ipc
        function next(): void             { root._focusedPane = root._wrap ? (root._focusedPane + 1) % root._panes.length : Math.min(root._panes.length - 1, root._focusedPane + 1) }
        // ui+ipc
        function prev(): void             { root._focusedPane = root._wrap ? (root._focusedPane - 1 + root._panes.length) % root._panes.length : Math.max(0, root._focusedPane - 1) }
        // ipc only
        function seek(n: int): void       { root._focusedPane = Math.max(0, Math.min(root._panes.length - 1, n)) }
        // ui only
        function cyclePanes(): void       { root._focusedPane = (root._focusedPane + 1) % root._panes.length }
        // ui+ipc
        function toggleFullscreen(): void { root._fullscreen = !root._fullscreen }
        // ipc only
        function setFullscreen(on: bool): void { root._fullscreen = on }
        // ipc only
        function setWrap(on: bool): void  { root._wrap = on }
        // ui+ipc
        function quit(): void             { Qt.quit() }
        // ipc only
        function key(k: string): void {
            const lk = k.toLowerCase()
            if      (lk === "f")                    toggleFullscreen()
            else if (lk === "q" || lk === "escape") escapeOrQuit()
            else if (lk === "tab" && !root._fullscreen) cyclePanes()
            else if (root._fullscreen && (lk === "h" || lk === "left"))  prev()
            else if (root._fullscreen && (lk === "l" || lk === "right")) next()
            else {
                const pane = paneRepeater.itemAt(root._focusedPane)
                if (pane) pane.handleViewerIpcKey(k)
            }
        }
        // ui only
        function init(): void {
            historyStore.load()
            if (root._mode === "session") listProcess.running = true
        }
        // ui only
        function onListRead(line: string): void {
            if (line.trim() === "") return
            const parts = line.split("\t")
            root._listItems.push({ path: parts[0] ?? "", label: parts[1] ?? "", desc: parts[2] ?? "" })
        }
        // ui only
        function onListExited(): void {
            if (root._listItems.length === 0) { Qt.quit(); return }
            root._panes     = root._listItems.slice()
            root._listItems = []
            root._ready     = true
        }
        // ui only — history has finished loading; handle auto-recall and focus
        function onHistoryLoaded(): void {
            if (root._mode !== "browser") return
            // --recall <N> ships us here with _autoRecallIdx set; commit that
            // entry straight away so the user lands in the session view.
            if (root._autoRecallIdx > 0) {
                const rows = _sortedHistory().slice().reverse()
                if (root._autoRecallIdx >= 1 && root._autoRecallIdx <= rows.length) {
                    openSessionFromPicker(rows[root._autoRecallIdx - 1])
                    return
                }
            }
            pickerSearch.forceActiveFocus()
        }
        // ui only — history entries sorted oldest→newest by epoch key
        function _sortedHistory(): var {
            const rows = []
            for (const [ts, json] of Object.entries(historyStore.values)) {
                try {
                    rows.push({ ts: parseInt(ts, 10), items: JSON.parse(json) })
                } catch (_) { /* skip malformed entry */ }
            }
            rows.sort((a, b) => a.ts - b.ts)
            return rows
        }
        // ipc only — 1-indexed from newest
        function recall(n: int): void {
            const rows = _sortedHistory()
            if (n < 1 || n > rows.length) return
            const entry = rows[rows.length - n]
            if (!entry.items || entry.items.length === 0) return
            openSessionFromPicker(entry)
        }
        // ipc only — newest first, 1-indexed; one TSV line per entry
        function listHistory(): string {
            const rows  = _sortedHistory()
            const lines = []
            for (let i = rows.length - 1; i >= 0; i--) {
                const e     = rows[i]
                const idx   = rows.length - i
                const count = e.items.length
                const first = e.items[0] || {}
                const head  = first.label || first.path || ""
                lines.push(idx + "\t" + e.ts + "\t" + count + "\t" + head)
            }
            return lines.join("\n")
        }
        // ui only — transition from browser mode into a session view
        function openSessionFromPicker(entry): void {
            if (!entry || !entry.items || entry.items.length === 0) return
            root._panes           = entry.items.slice()
            root._listItems       = []
            root._focusedPane     = 0
            root._fullscreen      = false
            root._ready           = true
            root._cameFromBrowser = true
            root._mode            = "session"
            keyHandler.forceActiveFocus()
        }
        // ui only — session Esc: back to browser if we came from there, else quit
        function escapeOrQuit(): void {
            if (root._cameFromBrowser) {
                root._panes       = []
                root._ready       = false
                root._fullscreen  = false
                root._focusedPane = 0
                root._mode        = "browser"
                pickerSearch.text = ""
                root._pickerSearch = ""
                root._pickerMode  = "insert"
                pickerSearch.forceActiveFocus()
                return
            }
            quit()
        }
        // ui only
        function onShow(): void { if (root._mode === "session") keyHandler.forceActiveFocus() }
        // ui only
        function onYankTextRequested(t: string): void { impl.yank(t) }
        // ui only
        function handleKeyEvent(event): void {
            if (event.key === Qt.Key_Shift   || event.key === Qt.Key_Control ||
                event.key === Qt.Key_Alt     || event.key === Qt.Key_Meta) return
            if (event.text === "q" || event.key === Qt.Key_Escape)            { escapeOrQuit();     event.accepted = true; return }
            if (event.text === "f" && root._panes.length > 1)                 { toggleFullscreen(); event.accepted = true; return }
            if (root._fullscreen && (event.key === Qt.Key_H || event.key === Qt.Key_Left))  { prev(); event.accepted = true; return }
            if (root._fullscreen && (event.key === Qt.Key_L || event.key === Qt.Key_Right)) { next(); event.accepted = true; return }
            if (!root._fullscreen && event.key === Qt.Key_Tab && root._panes.length > 1) { cyclePanes(); event.accepted = true; return }
            const pane = paneRepeater.itemAt(root._focusedPane)
            if (pane) event.accepted = pane.handleViewerKey(event)
        }

        // ── Picker ───────────────────────────────────────────────────────────
        // ui only
        function pickerCommit(): void {
            const entry = root._pickerFiltered[pickerList.currentIndex]
            if (entry) openSessionFromPicker(entry)
        }
        // ui only — search field text change: refilter + reset cursor
        function pickerSearchChanged(): void {
            root._pickerSearch = pickerSearch.text
            pickerList.currentIndex = 0
        }
        // ui only — insert → normal mode
        function pickerSearchEscape(): void {
            root._pickerMode = "normal"
            pickerKeyHandler.forceActiveFocus()
        }
        // ui only — `/` from normal → insert mode
        function pickerEnterInsert(): void {
            root._pickerMode = "insert"
            pickerSearch.forceActiveFocus()
        }
        // ui only — navigation in normal mode
        function pickerNav(delta: int): void {
            if (root._pickerCount === 0) return
            pickerList.currentIndex = Math.max(
                0, Math.min(root._pickerCount - 1, pickerList.currentIndex + delta))
        }
        // ui only — key dispatch in picker normal mode
        function pickerNormalKey(event): void {
            if (event.key === Qt.Key_Shift   || event.key === Qt.Key_Control ||
                event.key === Qt.Key_Alt     || event.key === Qt.Key_Meta) return
            if (event.key === Qt.Key_Escape || event.text === "q") { quit(); event.accepted = true; return }
            if (event.text === "/")                                { pickerEnterInsert(); event.accepted = true; return }
            if (event.key === Qt.Key_J || event.key === Qt.Key_Down)     { pickerNav(1);  event.accepted = true; return }
            if (event.key === Qt.Key_K || event.key === Qt.Key_Up)       { pickerNav(-1); event.accepted = true; return }
            if (event.key === Qt.Key_G && (event.modifiers & Qt.ShiftModifier)) { pickerList.currentIndex = Math.max(0, root._pickerCount - 1); event.accepted = true; return }
            if (event.key === Qt.Key_G)                                   { pickerList.currentIndex = 0; event.accepted = true; return }
            if (event.key === Qt.Key_D && (event.modifiers & Qt.ControlModifier)) { pickerNav( 5); event.accepted = true; return }
            if (event.key === Qt.Key_U && (event.modifiers & Qt.ControlModifier)) { pickerNav(-5); event.accepted = true; return }
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { pickerCommit(); event.accepted = true; return }
        }
    }

    IpcHandler {
        target: "view"

        readonly property int    currentIndex: root._focusedPane
        readonly property int    count:        root._panes.length
        readonly property bool   fullscreen:   root._fullscreen
        readonly property bool   wrap:         root._wrap
        readonly property bool   hasPrev:      root._wrap || root._focusedPane > 0
        readonly property bool   hasNext:      root._wrap || root._focusedPane < root._panes.length - 1
        readonly property int    historyCount: Object.keys(historyStore.values).length
        readonly property string mode:         root._mode

        function quit()                  { functionality.quit() }
        function next()                  { functionality.next() }
        function prev()                  { functionality.prev() }
        function seek(n: int)            { functionality.seek(n) }
        function setFullscreen(on: bool) { functionality.setFullscreen(on) }
        function setWrap(on: bool)       { functionality.setWrap(on) }
        function key(k: string)          { functionality.key(k) }
        function recall(n: int)          { functionality.recall(n) }
        function listHistory(): string   { return functionality.listHistory() }
    }

    // ── Yank ──────────────────────────────────────────────────────────────────
    Process { id: yankProcess }

    QtObject {
        id: impl
        function yank(text: string): void {
            yankProcess.command = [bin.bash, "-c", "printf '%s' \"$1\" | " + bin.wlCopy, "--", text]
            yankProcess.running = true
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────
    function _formatTs(ts: int): string {
        const d = new Date(ts * 1000)
        const pad = (n) => n < 10 ? "0" + n : "" + n
        return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate())
             + " " + pad(d.getHours()) + ":" + pad(d.getMinutes())
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

        // ── Session view ──────────────────────────────────────────────────────
        Item {
            id: keyHandler
            anchors.fill: parent
            focus: root._mode === "session"
            visible: root._mode === "session"
            Component.onCompleted: functionality.onShow()

            readonly property int _paneWidth: root._panes.length > 0
                ? Math.floor(width / root._panes.length) : width

            Keys.onPressed: (event) => functionality.handleKeyEvent(event)

            Repeater {
                id: paneRepeater
                model: root._ready ? root._panes : []

                delegate: Item {
                    id: pane
                    required property var modelData  // { path, label, desc }
                    required property int    index

                    visible: !root._fullscreen || pane.index === root._focusedPane
                    x:      root._fullscreen ? 0 : pane.index * keyHandler._paneWidth
                    width:  root._fullscreen ? keyHandler.width
                            : pane.index < root._panes.length - 1
                              ? keyHandler._paneWidth
                              : keyHandler.width - pane.index * keyHandler._paneWidth
                    height: keyHandler.height

                    property string _text:    ""
                    property bool   _isImage: false
                    property string _imgSrc:  ""
                    property bool   _loading: true
                    property bool   _missing: false
                    property var    _lines:   []
                    readonly property int  _headerH:  pane.modelData.label ? 44 : 0
                    readonly property bool _hasDots:  root._fullscreen && root._panes.length > 1
                    readonly property int  _dotsGap:  pane._hasDots ? 40 : 0

                    function handleViewerKey(event)      { return paneViewer.handleKey(event) }
                    function handleViewerIpcKey(k: string) { return paneViewer.handleIpcKey(k) }

                    QtObject {
                        id: paneFunctionality
                        // ui only
                        function init(): void {
                            const ext = pane.modelData.path.split(".").pop().toLowerCase()
                            pane._isImage = ["png","jpg","jpeg","gif","webp","bmp","svg"].includes(ext)
                            existsCheck.running = true
                        }
                        // ui only
                        function onExistsChecked(exists: bool): void {
                            if (!exists) {
                                pane._missing = true
                                pane._loading = false
                                return
                            }
                            if (pane._isImage) { pane._imgSrc = "file://" + pane.modelData.path; pane._loading = false }
                            else               readProc.running = true
                        }
                        // ui only
                        function onReadLine(line: string): void { pane._lines.push(line) }
                        // ui only
                        function onReadExited(): void {
                            pane._text    = pane._lines.join("\n")
                            pane._lines   = []
                            pane._loading = false
                        }
                    }

                    Component.onCompleted: paneFunctionality.init()

                    Process {
                        id: existsCheck
                        command: [bin.bash, "-c", "[ -e \"$1\" ]", "--", pane.modelData.path]
                        onExited: (exitCode) => paneFunctionality.onExistsChecked(exitCode === 0)
                    }

                    Process {
                        id: readProc
                        command: [bin.bash, "-c", "cat -- \"$1\"", "--", pane.modelData.path]
                        stdout: SplitParser {
                            onRead: (line) => paneFunctionality.onReadLine(line)
                        }
                        onExited: paneFunctionality.onReadExited()
                    }

                    // Divider on the left edge (split mode only, not first pane)
                    Rectangle {
                        visible: !root._fullscreen && pane.index > 0
                        x: 0; width: 1; height: parent.height
                        color: root._focusedPane === pane.index ? cfg.color.base0D : cfg.color.base02
                    }

                    // Pane label — centered at the bottom (above dots in fullscreen with multiple panes)
                    Item {
                        id: paneHeader
                        visible: pane.modelData.label !== ""
                        anchors { left: parent.left; right: parent.right }
                        y: parent.height - pane._headerH - pane._dotsGap
                        height: pane._headerH

                        Rectangle {
                            anchors.centerIn: parent
                            width:  labelRow.width + 32
                            height: labelRow.height + 14
                            radius: 8
                            color: cfg.color.base01
                            border.width: 1
                            border.color: cfg.color.base02

                            Row {
                                id: labelRow
                                anchors.centerIn: parent
                                spacing: 14

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: pane.modelData.label
                                    color: cfg.color.base07
                                    font.family: cfg.fontFamily
                                    font.pixelSize: cfg.fontSize + 6
                                    font.bold: true
                                }

                                Text {
                                    visible: pane.modelData.desc !== ""
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "·"
                                    color: cfg.color.base04
                                    font.family: cfg.fontFamily
                                    font.pixelSize: cfg.fontSize + 6
                                }

                                Text {
                                    visible: pane.modelData.desc !== ""
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: pane.modelData.desc
                                    color: cfg.color.base05
                                    font.family: cfg.fontFamily
                                    font.pixelSize: cfg.fontSize + 2
                                }
                            }
                        }
                    }

                    // Placeholder shown when the file does not exist on disk
                    Item {
                        visible: pane._missing
                        anchors {
                            top: parent.top
                            left: parent.left; right: parent.right; bottom: parent.bottom
                            bottomMargin: pane._headerH + pane._dotsGap
                        }

                        Column {
                            anchors.centerIn: parent
                            spacing: 10

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: pane._isImage ? "image missing" : "file missing"
                                color: cfg.color.base03
                                font.family: cfg.fontFamily
                                font.pixelSize: cfg.fontSize + 4
                                font.bold: true
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: pane.modelData.path
                                color: cfg.color.base03
                                font.family: cfg.fontFamily
                                font.pixelSize: cfg.fontSize - 1
                                elide: Text.ElideMiddle
                                width: Math.min(pane.width - 60, 600)
                                horizontalAlignment: Text.AlignHCenter
                            }
                        }
                    }

                    ContentViewer {
                        id: paneViewer
                        visible: !pane._missing
                        anchors {
                            top: parent.top
                            left: parent.left; right: parent.right; bottom: parent.bottom
                            bottomMargin: pane._headerH + pane._dotsGap
                        }

                        text:        pane._text
                        isImage:     pane._isImage
                        imageSource: pane._imgSrc
                        focused:     root._focusedPane === pane.index
                        loading:     pane._loading

                        textColor:          cfg.color.base05
                        selectionColor:     cfg.color.base0D
                        selectionTextColor: cfg.color.base00
                        cursorColor:        cfg.color.base07
                        dimColor:           cfg.color.base03
                        fontFamily:         cfg.fontFamily
                        fontSize:           cfg.fontSize

                        onYankTextRequested: (t) => functionality.onYankTextRequested(t)
                    }
                }
            }

            // Fullscreen mode dot indicators
            Row {
                visible: root._fullscreen && root._panes.length > 1
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottomMargin: 16
                spacing: 8

                Repeater {
                    model: root._ready ? root._panes.length : 0
                    delegate: Rectangle {
                        required property int index
                        width: 8; height: 8; radius: 4
                        color: index === root._focusedPane ? cfg.color.base05 : cfg.color.base03
                    }
                }
            }

            // "Back to History" pill — only visible when we reached this session
            // via the browser, so Esc takes us back instead of quitting.
            Rectangle {
                visible: root._cameFromBrowser
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.leftMargin: 20
                anchors.topMargin: 20
                height: 30
                width: pillRow.width + 20
                radius: 15
                color: cfg.color.base01
                border.width: 1
                border.color: cfg.color.base02

                Row {
                    id: pillRow
                    anchors.centerIn: parent
                    spacing: 6

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Esc"
                        color: cfg.color.base0D
                        font.family: cfg.fontFamily
                        font.pixelSize: cfg.fontSize - 2
                        font.bold: true
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Back to History"
                        color: cfg.color.base05
                        font.family: cfg.fontFamily
                        font.pixelSize: cfg.fontSize - 2
                    }
                }
            }
        }

        // ── History browser ───────────────────────────────────────────────────
        Item {
            id: pickerKeyHandler
            anchors.fill: parent
            focus: root._mode === "browser" && root._pickerMode === "normal"
            visible: root._mode === "browser"

            Keys.onPressed: (event) => functionality.pickerNormalKey(event)

            // Panel chrome
            Rectangle {
                id: pickerPanel
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: Math.round(parent.height * 0.08)
                width:  Math.round(parent.width * 0.5)
                height: Math.round(parent.height * 0.7)
                color: cfg.color.base01
                radius: 12

                Column {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 10

                    // Search bar
                    Rectangle {
                        id: pickerSearchBox
                        width: parent.width
                        height: 40
                        color: cfg.color.base02
                        radius: 6

                        TextInput {
                            id: pickerSearch
                            anchors.fill: parent
                            anchors.leftMargin: 14
                            anchors.rightMargin: 14
                            color: cfg.color.base05
                            font.family: cfg.fontFamily
                            font.pixelSize: cfg.fontSize
                            verticalAlignment: TextInput.AlignVCenter
                            clip: true
                            readOnly: root._pickerMode !== "insert"
                            focus: root._mode === "browser" && root._pickerMode === "insert"

                            onTextChanged:        functionality.pickerSearchChanged()
                            Keys.onEscapePressed: functionality.pickerSearchEscape()
                            Keys.onReturnPressed: functionality.pickerCommit()

                            Text {
                                anchors.fill: parent
                                visible: !pickerSearch.text
                                text: "Search history..."
                                color: cfg.color.base03
                                font.family: cfg.fontFamily
                                font.pixelSize: cfg.fontSize
                                verticalAlignment: Text.AlignVCenter
                            }
                        }
                    }

                    // Entry list (or empty-state)
                    ListView {
                        id: pickerList
                        width: parent.width
                        height: parent.height - pickerSearchBox.height - pickerFooter.height - parent.spacing * 2
                        clip: true
                        currentIndex: 0
                        highlightMoveDuration: 0
                        model: root._pickerFiltered

                        Text {
                            anchors.centerIn: parent
                            visible: root._pickerCount === 0
                            text: root._pickerSearch ? "No matches" : "(no history)"
                            color: cfg.color.base03
                            font.family: cfg.fontFamily
                            font.pixelSize: cfg.fontSize
                        }

                        delegate: Item {
                            required property var modelData     // { ts, items }
                            required property int index
                            width: pickerList.width
                            height: 36

                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: 2
                                radius: 4
                                color: pickerList.currentIndex === parent.index ? cfg.color.base02 : "transparent"
                            }

                            Row {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                spacing: 14

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: root._formatTs(parent.parent.modelData.ts || 0)
                                    color: cfg.color.base04
                                    font.family: cfg.fontFamily
                                    font.pixelSize: cfg.fontSize
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: {
                                        const n = (parent.parent.modelData.items || []).length
                                        return n + (n === 1 ? " item" : " items")
                                    }
                                    color: cfg.color.base05
                                    font.family: cfg.fontFamily
                                    font.pixelSize: cfg.fontSize
                                }
                            }
                        }
                    }

                    // Footer hint
                    Item {
                        id: pickerFooter
                        width: parent.width
                        height: 20

                        Text {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: root._pickerMode === "insert"
                                ? "Esc normal mode  \u00b7  Enter open"
                                : "j/k navigate  \u00b7  Enter open  \u00b7  / search  \u00b7  Esc quit"
                            color: cfg.color.base03
                            font.family: cfg.fontFamily
                            font.pixelSize: cfg.fontSize - 3
                        }
                        Text {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: root._pickerCount + " / " + Object.keys(historyStore.values).length
                            color: cfg.color.base03
                            font.family: cfg.fontFamily
                            font.pixelSize: cfg.fontSize - 3
                        }
                    }
                }
            }
        }
    }
}
