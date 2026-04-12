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
    property bool   fullscreenShowing: false
    property int    _visualAnchor: 0
    // "" | "char" | "line" | "block" — active in whichever text pane is focused
    property string _visualMode: ""
    property int    _visualAnchorPos: 0   // char/line: anchor char index
    property int    _visualAnchorRow: 0   // line/block: anchor logical row
    property int    _visualAnchorCol: 0   // block: anchor logical col
    property int    _visualCurRow: 0      // line/block: current logical row
    property int    _visualCurCol: 0      // block: current logical col

    readonly property bool _detailVisual: _visualMode !== "" && detailFocused
    readonly property bool _fsVisual:     _visualMode !== "" && fullscreenShowing

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

    function yankText(text) {
        yankTextProcess.command = [
            bin.bash, "-c", "printf '%s' \"$1\" | " + bin.wlCopy, "--", text
        ]
        yankTextProcess.running = true
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

    function enterVisualMode() {
        root._visualAnchor = resultList.currentIndex
        root.mode = "visual"
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

    function openFullscreen() {
        root.fullscreenShowing = true
        fullscreenFlick.contentY = 0
        normalModeHandler.forceActiveFocus()
    }

    function closeFullscreen() {
        root.fullscreenShowing = false
        root._visualMode = ""
        normalModeHandler.forceActiveFocus()
    }

    // ── Text-visual helpers ──────────────────────────────────────────────────
    function _logicalLineAt(text, pos) {
        let n = 0
        for (let i = 0; i < pos && i < text.length; i++)
            if (text[i] === '\n') n++
        return n
    }

    function _lineStartAt(text, row) {
        let n = 0, i = 0
        while (i < text.length && n < row) {
            if (text[i] === '\n') n++
            i++
        }
        return i
    }

    function _lineEndAt(text, row) {
        let i = root._lineStartAt(text, row)
        while (i < text.length && text[i] !== '\n') i++
        return i
    }

    function _lineCount(text) {
        if (!text) return 1
        let n = 1
        for (let i = 0; i < text.length; i++)
            if (text[i] === '\n') n++
        return n
    }

    function _scrollEditIntoView(edit, flick, pos) {
        const r = edit.positionToRectangle(pos)
        if (r.y + r.height > flick.contentY + flick.height)
            flick.contentY = Math.min(Math.max(0, flick.contentHeight - flick.height),
                                      r.y + r.height - flick.height)
        else if (r.y < flick.contentY)
            flick.contentY = Math.max(0, r.y)
    }

    function _applyLineSelection(edit) {
        const text = edit.text
        const lo   = Math.min(root._visualAnchorRow, root._visualCurRow)
        const hi   = Math.max(root._visualAnchorRow, root._visualCurRow)
        const start = root._lineStartAt(text, lo)
        const end   = root._lineEndAt(text, hi)
        if (root._visualCurRow >= root._visualAnchorRow) edit.select(start, end)
        else                                              edit.select(end, start)
    }

    function _enterTextVisual(mode, edit, flick) {
        const sp   = edit.cursorPosition   // start from current cursor, not viewport top
        const text = edit.text
        root._visualMode = mode
        if (mode === "char") {
            root._visualAnchorPos = sp
            edit.select(sp, sp)
        } else if (mode === "line") {
            const row = root._logicalLineAt(text, sp)
            root._visualAnchorRow = row
            root._visualCurRow    = row
            root._visualAnchorPos = root._lineStartAt(text, row)
            root._applyLineSelection(edit)
        } else if (mode === "block") {
            const row = root._logicalLineAt(text, sp)
            const col = sp - root._lineStartAt(text, row)
            root._visualAnchorRow = row; root._visualAnchorCol = col
            root._visualCurRow    = row; root._visualCurCol    = col
            root._visualAnchorPos = sp
            edit.select(0, 0)
        }
    }

    function _handleTextVisualKey(event, edit, flick) {
        const text = edit.text

        // ── Exit / mode-switch ───────────────────────────────────────────────
        if (event.key === Qt.Key_Escape) {
            const cp = edit.cursorPosition
            root._visualMode = ""; edit.select(cp, cp); return true   // keep cursor, clear selection
        }
        if (event.text === "v") {
            if (root._visualMode === "char") {
                const cp = edit.cursorPosition
                root._visualMode = ""; edit.select(cp, cp)
            } else {
                // Switch to char mode at the current cursor position
                let cp = edit.cursorPosition
                if (root._visualMode === "block") {
                    const ls = root._lineStartAt(text, root._visualCurRow)
                    cp = Math.min(ls + root._visualCurCol, root._lineEndAt(text, root._visualCurRow))
                }
                root._visualMode = "char"; root._visualAnchorPos = cp
                edit.select(cp, cp)
            }
            return true
        }
        if (event.text === "V") {
            if (root._visualMode === "line") {
                const cp = edit.cursorPosition
                root._visualMode = ""; edit.select(cp, cp)
            } else {
                const cp  = edit.cursorPosition
                const cur = root._logicalLineAt(text, cp)
                const anc = root._logicalLineAt(text, root._visualAnchorPos)
                root._visualMode = "line"
                root._visualAnchorRow = anc; root._visualCurRow = cur
                root._visualAnchorPos = root._lineStartAt(text, anc)
                root._applyLineSelection(edit)
            }
            return true
        }
        if (event.key === Qt.Key_V && (event.modifiers & Qt.ControlModifier)) {
            if (root._visualMode === "block") { root._visualMode = "" }
            else {
                const cp   = edit.cursorPosition
                const cur  = root._logicalLineAt(text, cp)
                const ccol = cp - root._lineStartAt(text, cur)
                const anc  = root._logicalLineAt(text, root._visualAnchorPos)
                const acol = root._visualAnchorPos - root._lineStartAt(text, anc)
                root._visualMode = "block"
                root._visualAnchorRow = anc; root._visualAnchorCol = acol
                root._visualCurRow    = cur; root._visualCurCol    = ccol
                root._visualAnchorPos = root._lineStartAt(text, anc) + acol
                edit.select(0, 0)
            }
            return true
        }

        // ── Char mode ────────────────────────────────────────────────────────
        if (root._visualMode === "char") {
            if (event.text === "y") {
                const sel = edit.selectedText
                if (sel) root.yankText(sel); else root.yank(root.selectedEntry)
                root._visualMode = ""; edit.select(0, 0); return true
            }
            if (event.text === "o" || event.text === "O") {
                const oldAnchor = root._visualAnchorPos, oldCursor = edit.cursorPosition
                root._visualAnchorPos = oldCursor
                edit.select(oldCursor, oldAnchor); return true
            }
            if (event.key === Qt.Key_J || event.key === Qt.Key_Down) {
                const r  = edit.positionToRectangle(edit.cursorPosition)
                const np = edit.positionAt(edit.leftPadding, r.y + r.height + 1)
                if (np !== edit.cursorPosition) {
                    edit.moveCursorSelection(np, TextEdit.SelectCharacters)
                    root._scrollEditIntoView(edit, flick, np)
                }
                return true
            }
            if (event.key === Qt.Key_K || event.key === Qt.Key_Up) {
                const r  = edit.positionToRectangle(edit.cursorPosition)
                const np = edit.positionAt(edit.leftPadding, r.y - 1)
                if (np !== edit.cursorPosition) {
                    edit.moveCursorSelection(np, TextEdit.SelectCharacters)
                    root._scrollEditIntoView(edit, flick, np)
                }
                return true
            }
            return false
        }

        // ── Line mode ────────────────────────────────────────────────────────
        if (root._visualMode === "line") {
            if (event.text === "y") {
                const lo = Math.min(root._visualAnchorRow, root._visualCurRow)
                const hi = Math.max(root._visualAnchorRow, root._visualCurRow)
                root.yankText(text.substring(root._lineStartAt(text, lo), root._lineEndAt(text, hi)))
                root._visualMode = ""; edit.select(0, 0); return true
            }
            if (event.text === "o" || event.text === "O") {
                const tmp = root._visualAnchorRow
                root._visualAnchorRow = root._visualCurRow; root._visualCurRow = tmp
                root._applyLineSelection(edit)
                root._scrollEditIntoView(edit, flick, edit.cursorPosition); return true
            }
            if (event.key === Qt.Key_J || event.key === Qt.Key_Down) {
                const max = root._lineCount(text) - 1
                if (root._visualCurRow < max) {
                    root._visualCurRow++
                    root._applyLineSelection(edit)
                    root._scrollEditIntoView(edit, flick, edit.cursorPosition)
                }
                return true
            }
            if (event.key === Qt.Key_K || event.key === Qt.Key_Up) {
                if (root._visualCurRow > 0) {
                    root._visualCurRow--
                    root._applyLineSelection(edit)
                    root._scrollEditIntoView(edit, flick, edit.cursorPosition)
                }
                return true
            }
            return false
        }

        // ── Block mode ───────────────────────────────────────────────────────
        if (root._visualMode === "block") {
            if (event.text === "y") {
                const lo    = Math.min(root._visualAnchorRow, root._visualCurRow)
                const hi    = Math.max(root._visualAnchorRow, root._visualCurRow)
                const loCol = Math.min(root._visualAnchorCol, root._visualCurCol)
                const hiCol = Math.max(root._visualAnchorCol, root._visualCurCol)
                const lines = []
                for (let row = lo; row <= hi; row++) {
                    const ls = root._lineStartAt(text, row), le = root._lineEndAt(text, row)
                    lines.push(text.substring(ls, le).substring(loCol, hiCol + 1))
                }
                root.yankText(lines.join("\n"))
                root._visualMode = ""; return true
            }
            if (event.text === "o") {
                // Swap to diagonally opposite corner
                const tr = root._visualAnchorRow, tc = root._visualAnchorCol
                root._visualAnchorRow = root._visualCurRow; root._visualAnchorCol = root._visualCurCol
                root._visualCurRow    = tr;                 root._visualCurCol    = tc; return true
            }
            if (event.text === "O") {
                // Swap to same-row opposite column
                const tc = root._visualAnchorCol
                root._visualAnchorCol = root._visualCurCol; root._visualCurCol = tc; return true
            }
            if (event.key === Qt.Key_J || event.key === Qt.Key_Down) {
                const max = root._lineCount(text) - 1
                if (root._visualCurRow < max) root._visualCurRow++; return true
            }
            if (event.key === Qt.Key_K || event.key === Qt.Key_Up) {
                if (root._visualCurRow > 0) root._visualCurRow--; return true
            }
            if (event.key === Qt.Key_L || event.key === Qt.Key_Right) {
                root._visualCurCol++; return true
            }
            if (event.key === Qt.Key_H || event.key === Qt.Key_Left) {
                if (root._visualCurCol > 0) root._visualCurCol--; return true
            }
            return false
        }

        return false
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
        root._visualMode     = ""
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
    Process { id: yankTextProcess }

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
            else if (v === "fullscreen") root.openFullscreen()
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
            } else if (lk === "v" && !root.helpShowing) {
                if (root.fullscreenShowing && !root._detailIsImage) {
                    if (root._visualMode !== "") { root._visualMode = ""; fsTextEdit.select(0, 0) }
                    else root._enterTextVisual("char", fsTextEdit, fullscreenFlick)
                } else if (root.detailFocused && !root._detailIsImage) {
                    if (root._visualMode !== "") { root._visualMode = ""; detailTextEdit.select(0, 0) }
                    else root._enterTextVisual("char", detailTextEdit, detailFlick)
                } else {
                    if (root.mode === "visual") root.mode = "normal"
                    else root.enterVisualMode()
                }
            } else if (lk === "l" && !root.helpShowing) {
                root.detailFocused = true
            } else if (lk === "h" && root.detailFocused) {
                root.detailFocused = false
            } else if (lk === "enter" || lk === "return") {
                if (root.detailFocused && !root.fullscreenShowing) root.openFullscreen()
            } else if (lk === "escape" || lk === "esc") {
                if (root.helpShowing) {
                    if (root.helpText) { root.helpText = ""; root._helpFiltering = false }
                    else root.closeHelp()
                } else if (root.fullscreenShowing) {
                    root.closeFullscreen()
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
                root.helpShowing      = false
                root._helpFiltering   = false
                root.helpText         = ""
                root.detailFocused    = false
                root.fullscreenShowing = false
                root._visualMode      = ""
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

                    // ── Fullscreen ────────────────────────────────────────────
                    if (root.fullscreenShowing) {
                        if (root._visualMode !== "") {
                            if (root._handleTextVisualKey(event, fsTextEdit, fullscreenFlick))
                                event.accepted = true
                            return
                        }
                        const lineH = cfg.fontSize + 6
                        const halfPg = Math.max(lineH, Math.floor(fullscreenFlick.height / 2))
                        if (event.key === Qt.Key_Escape) {
                            root.closeFullscreen()
                        } else if (event.text === "v" && !root._detailIsImage) {
                            root._enterTextVisual("char", fsTextEdit, fullscreenFlick)
                        } else if (event.text === "V" && !root._detailIsImage) {
                            root._enterTextVisual("line", fsTextEdit, fullscreenFlick)
                        } else if (event.key === Qt.Key_V && (event.modifiers & Qt.ControlModifier) && !root._detailIsImage) {
                            root._enterTextVisual("block", fsTextEdit, fullscreenFlick)
                        } else if (event.text === "y") {
                            if (root.selectedEntry !== "") root.yank(root.selectedEntry)
                        } else if (!root._detailIsImage && (event.key === Qt.Key_J || event.key === Qt.Key_Down)) {
                            const r  = fsTextEdit.positionToRectangle(fsTextEdit.cursorPosition)
                            const np = fsTextEdit.positionAt(fsTextEdit.leftPadding, r.y + r.height + 1)
                            if (np !== fsTextEdit.cursorPosition) {
                                fsTextEdit.select(np, np)
                                root._scrollEditIntoView(fsTextEdit, fullscreenFlick, np)
                            }
                        } else if (!root._detailIsImage && (event.key === Qt.Key_K || event.key === Qt.Key_Up)) {
                            const r  = fsTextEdit.positionToRectangle(fsTextEdit.cursorPosition)
                            const np = fsTextEdit.positionAt(fsTextEdit.leftPadding, r.y - 1)
                            if (np !== fsTextEdit.cursorPosition) {
                                fsTextEdit.select(np, np)
                                root._scrollEditIntoView(fsTextEdit, fullscreenFlick, np)
                            }
                        } else if (!root._detailIsImage && event.key === Qt.Key_D && (event.modifiers & Qt.ControlModifier)) {
                            fullscreenFlick.contentY = Math.min(
                                Math.max(0, fullscreenFlick.contentHeight - fullscreenFlick.height),
                                fullscreenFlick.contentY + halfPg)
                        } else if (!root._detailIsImage && event.key === Qt.Key_U && (event.modifiers & Qt.ControlModifier)) {
                            fullscreenFlick.contentY = Math.max(0, fullscreenFlick.contentY - halfPg)
                        } else if (!root._detailIsImage && event.key === Qt.Key_G && (event.modifiers & Qt.ShiftModifier)) {
                            fullscreenFlick.contentY = Math.max(0, fullscreenFlick.contentHeight - fullscreenFlick.height)
                        } else if (!root._detailIsImage && event.key === Qt.Key_G) {
                            fullscreenFlick.contentY = 0
                        } else {
                            return
                        }
                        event.accepted = true
                        return
                    }

                    // ── Visual mode ───────────────────────────────────────────
                    if (root.mode === "visual") {
                        if (event.key === Qt.Key_Escape || event.text === "v") {
                            root.mode = "normal"
                        } else if (event.key === Qt.Key_J || event.key === Qt.Key_Down) {
                            root.navDown()
                        } else if (event.key === Qt.Key_K || event.key === Qt.Key_Up) {
                            root.navUp()
                        } else if (event.key === Qt.Key_G && (event.modifiers & Qt.ShiftModifier)) {
                            root.navBottom()
                        } else if (event.key === Qt.Key_G) {
                            if (root._pendingG) { gTimer.stop(); root.navTop(); root._pendingG = false }
                            else { root._pendingG = true; gTimer.restart() }
                        } else if (event.key === Qt.Key_D && (event.modifiers & Qt.ControlModifier)) {
                            root.navHalfDown()
                        } else if (event.key === Qt.Key_U && (event.modifiers & Qt.ControlModifier)) {
                            root.navHalfUp()
                        } else {
                            return
                        }
                        event.accepted = true
                        return
                    }

                    // ── Detail focus ──────────────────────────────────────────
                    if (root.detailFocused) {
                        if (root._visualMode !== "") {
                            if (root._handleTextVisualKey(event, detailTextEdit, detailFlick))
                                event.accepted = true
                            return
                        }
                        const lineH = cfg.fontSize + 6
                        const halfPg = Math.max(lineH, Math.floor(detailFlick.height / 2))
                        if (event.key === Qt.Key_H || event.key === Qt.Key_Escape) {
                            root.detailFocused = false
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            root.openFullscreen()
                        } else if (event.text === "y") {
                            if (root.selectedEntry !== "") root.yank(root.selectedEntry)
                        } else if (event.text === "v" && !root._detailIsImage) {
                            root._enterTextVisual("char", detailTextEdit, detailFlick)
                        } else if (event.text === "V" && !root._detailIsImage) {
                            root._enterTextVisual("line", detailTextEdit, detailFlick)
                        } else if (event.key === Qt.Key_V && (event.modifiers & Qt.ControlModifier) && !root._detailIsImage) {
                            root._enterTextVisual("block", detailTextEdit, detailFlick)
                        } else if (!root._detailIsImage && (event.key === Qt.Key_J || event.key === Qt.Key_Down)) {
                            const r  = detailTextEdit.positionToRectangle(detailTextEdit.cursorPosition)
                            const np = detailTextEdit.positionAt(detailTextEdit.leftPadding, r.y + r.height + 1)
                            if (np !== detailTextEdit.cursorPosition) {
                                detailTextEdit.select(np, np)
                                root._scrollEditIntoView(detailTextEdit, detailFlick, np)
                            }
                        } else if (!root._detailIsImage && (event.key === Qt.Key_K || event.key === Qt.Key_Up)) {
                            const r  = detailTextEdit.positionToRectangle(detailTextEdit.cursorPosition)
                            const np = detailTextEdit.positionAt(detailTextEdit.leftPadding, r.y - 1)
                            if (np !== detailTextEdit.cursorPosition) {
                                detailTextEdit.select(np, np)
                                root._scrollEditIntoView(detailTextEdit, detailFlick, np)
                            }
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
                    } else if (event.text === "v") {
                        root.enterVisualMode()
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
                        visible: root.mode !== "insert"
                        width: modeLabel.implicitWidth + 12
                        height: 22
                        radius: 4
                        color: cfg.color.base02

                        Text {
                            id: modeLabel
                            anchors.centerIn: parent
                            text: {
                                if (root._visualMode === "char")  return "CHR"
                                if (root._visualMode === "line")  return "LIN"
                                if (root._visualMode === "block") return "BLK"
                                return root.mode === "visual" ? "VIS" : "NOR"
                            }
                            color: (root._visualMode !== "" || root.mode === "visual")
                                   ? cfg.color.base0E : cfg.color.base0D
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
                                color: {
                                    if (root.mode === "visual") {
                                        const lo = Math.min(root._visualAnchor, resultList.currentIndex)
                                        const hi = Math.max(root._visualAnchor, resultList.currentIndex)
                                        if (delegateRoot.index >= lo && delegateRoot.index <= hi)
                                            return delegateRoot.isCurrent ? cfg.color.base03 : cfg.color.base02
                                        return "transparent"
                                    }
                                    return delegateRoot.isCurrent ? cfg.color.base02 : "transparent"
                                }
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
                                contentHeight: detailTextEdit.implicitHeight
                                contentWidth: width
                                clip: true

                                // Block-visual overlay rectangles (Ctrl+V mode)
                                property var _blockRects: {
                                    if (root._visualMode !== "block" || !root.detailFocused || !root._detailText) return []
                                    const text  = root._detailText
                                    const lo    = Math.min(root._visualAnchorRow, root._visualCurRow)
                                    const hi    = Math.max(root._visualAnchorRow, root._visualCurRow)
                                    const loCol = Math.min(root._visualAnchorCol, root._visualCurCol)
                                    const hiCol = Math.max(root._visualAnchorCol, root._visualCurCol)
                                    const rects = []
                                    for (let row = lo; row <= hi; row++) {
                                        const ls = root._lineStartAt(text, row)
                                        const le = root._lineEndAt(text, row)
                                        const sp = ls + loCol <= le ? ls + loCol : le
                                        const ep = ls + hiCol <= le ? ls + hiCol : (le > 0 ? le - 1 : le)
                                        const sr = detailTextEdit.positionToRectangle(sp)
                                        const er = ep >= sp ? detailTextEdit.positionToRectangle(ep) : sr
                                        rects.push({ x: sr.x, y: sr.y, w: Math.max(4, er.x + er.width - sr.x), h: sr.height })
                                    }
                                    return rects
                                }

                                // Cursor position — visible whenever detail pane is focused on text
                                property rect _cursorRect: {
                                    if (!root.detailFocused || root._detailIsImage || root._detailLoading)
                                        return Qt.rect(0, 0, 0, 0)
                                    let pos
                                    if (root._visualMode === "block") {
                                        const text = root._detailText
                                        const ls = root._lineStartAt(text, root._visualCurRow)
                                        const le = root._lineEndAt(text, root._visualCurRow)
                                        pos = Math.min(ls + root._visualCurCol, le)
                                    } else {
                                        pos = detailTextEdit.cursorPosition
                                    }
                                    return detailTextEdit.positionToRectangle(pos)
                                }

                                TextEdit {
                                    id: detailTextEdit
                                    width: parent.width
                                    leftPadding: 12; rightPadding: 12; topPadding: 10; bottomPadding: 10
                                    text: root._detailText
                                    color: cfg.color.base05
                                    font.family: cfg.fontFamily
                                    font.pixelSize: cfg.fontSize
                                    wrapMode: TextEdit.Wrap
                                    readOnly: true
                                    selectByMouse: false
                                    selectByKeyboard: false
                                    cursorVisible: false
                                    selectedTextColor: cfg.color.base00
                                    selectionColor: cfg.color.base0D
                                }

                                Repeater {
                                    model: detailFlick._blockRects
                                    delegate: Rectangle {
                                        required property var modelData
                                        x: modelData.x; y: modelData.y
                                        width: modelData.w; height: modelData.h
                                        color: cfg.color.base0D; opacity: 0.4
                                    }
                                }

                                // Cursor bar — always visible when detail pane is focused on text
                                Rectangle {
                                    visible: root.detailFocused && !root._detailIsImage && !root._detailLoading
                                             && detailFlick._cursorRect.height > 0
                                    x: detailFlick._cursorRect.x
                                    y: detailFlick._cursorRect.y
                                    width: 2
                                    height: detailFlick._cursorRect.height
                                    color: cfg.color.base07
                                    z: 10
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
                        text: root._detailVisual
                            ? (root._visualMode === "char"
                                ? "v/Esc exit  \u00b7  j/k extend  \u00b7  o swap  \u00b7  V line  \u00b7  Ctrl+V block  \u00b7  y copy"
                               : root._visualMode === "line"
                                ? "V/Esc exit  \u00b7  j/k extend  \u00b7  o swap  \u00b7  v char  \u00b7  Ctrl+V block  \u00b7  y copy"
                               : "Ctrl+V/Esc exit  \u00b7  j/k/h/l move  \u00b7  o diag  \u00b7  O col  \u00b7  v char  \u00b7  y copy")
                            : root.detailFocused
                            ? "h/Esc list  \u00b7  j/k cursor  \u00b7  v/V/Ctrl+V visual  \u00b7  Enter fullscreen  \u00b7  y copy"
                            : root.mode === "visual"
                                ? "j/k  select  \u00b7  v / Esc  normal mode"
                                : root.mode === "normal"
                                    ? "j/k  navigate  \u00b7  v  visual  \u00b7  y  copy  \u00b7  l  detail  \u00b7  /  search  \u00b7  ?  help  \u00b7  Esc  close"
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

            // Fullscreen view ─────────────────────────────────────────────────
            Rectangle {
                anchors.fill: parent
                visible: root.fullscreenShowing
                z: 5
                color: cfg.color.base00
                clip: true

                // Header
                Item {
                    id: fsHeader
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 44

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 16
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
                        anchors.leftMargin: 72
                        anchors.right: parent.right
                        anchors.rightMargin: 16
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

                // Stats + hint bar
                Item {
                    id: fsStats
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 36

                    Rectangle {
                        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                        height: 1; color: cfg.color.base02
                    }
                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        color: cfg.color.base03
                        font.family: cfg.fontFamily
                        font.pixelSize: cfg.fontSize - 3
                        text: {
                            if (root._detailLoading) return ""
                            if (root._detailIsImage) {
                                const dim = fsImg.status === Image.Ready
                                    ? fsImg.implicitWidth + " \u00d7 " + fsImg.implicitHeight + " px"
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
                    Text {
                        anchors.right: parent.right
                        anchors.rightMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        text: root._fsVisual
                            ? (root._visualMode === "char"
                                ? "v/Esc exit  \u00b7  j/k extend  \u00b7  o swap  \u00b7  V line  \u00b7  Ctrl+V block  \u00b7  y copy"
                               : root._visualMode === "line"
                                ? "V/Esc exit  \u00b7  j/k extend  \u00b7  o swap  \u00b7  v char  \u00b7  Ctrl+V block  \u00b7  y copy"
                               : "Ctrl+V/Esc exit  \u00b7  j/k/h/l move  \u00b7  o diag  \u00b7  O col  \u00b7  v char  \u00b7  y copy")
                            : "Esc back  \u00b7  v/V/Ctrl+V visual  \u00b7  y copy"
                        color: cfg.color.base03
                        font.family: cfg.fontFamily
                        font.pixelSize: cfg.fontSize - 3
                    }
                }

                // Content
                Item {
                    anchors.top: fsHeader.bottom
                    anchors.bottom: fsStats.top
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
                        id: fullscreenFlick
                        anchors.fill: parent
                        visible: !root._detailIsImage && !root._detailLoading
                        contentHeight: fsTextEdit.implicitHeight
                        contentWidth: width
                        clip: true

                        // Block-visual overlay rectangles (Ctrl+V mode)
                        property var _blockRects: {
                            if (root._visualMode !== "block" || !root.fullscreenShowing || !root._detailText) return []
                            const text  = root._detailText
                            const lo    = Math.min(root._visualAnchorRow, root._visualCurRow)
                            const hi    = Math.max(root._visualAnchorRow, root._visualCurRow)
                            const loCol = Math.min(root._visualAnchorCol, root._visualCurCol)
                            const hiCol = Math.max(root._visualAnchorCol, root._visualCurCol)
                            const rects = []
                            for (let row = lo; row <= hi; row++) {
                                const ls = root._lineStartAt(text, row)
                                const le = root._lineEndAt(text, row)
                                const sp = ls + loCol <= le ? ls + loCol : le
                                const ep = ls + hiCol <= le ? ls + hiCol : (le > 0 ? le - 1 : le)
                                const sr = fsTextEdit.positionToRectangle(sp)
                                const er = ep >= sp ? fsTextEdit.positionToRectangle(ep) : sr
                                rects.push({ x: sr.x, y: sr.y, w: Math.max(4, er.x + er.width - sr.x), h: sr.height })
                            }
                            return rects
                        }

                        // Cursor position — visible whenever fullscreen is showing text
                        property rect _cursorRect: {
                            if (!root.fullscreenShowing || root._detailIsImage || root._detailLoading)
                                return Qt.rect(0, 0, 0, 0)
                            let pos
                            if (root._visualMode === "block") {
                                const text = root._detailText
                                const ls = root._lineStartAt(text, root._visualCurRow)
                                const le = root._lineEndAt(text, root._visualCurRow)
                                pos = Math.min(ls + root._visualCurCol, le)
                            } else {
                                pos = fsTextEdit.cursorPosition
                            }
                            return fsTextEdit.positionToRectangle(pos)
                        }

                        TextEdit {
                            id: fsTextEdit
                            width: parent.width
                            leftPadding: 16; rightPadding: 16; topPadding: 14; bottomPadding: 14
                            text: root._detailText
                            color: cfg.color.base05
                            font.family: cfg.fontFamily
                            font.pixelSize: cfg.fontSize
                            wrapMode: TextEdit.Wrap
                            readOnly: true
                            selectByMouse: false
                            selectByKeyboard: false
                            cursorVisible: false
                            selectedTextColor: cfg.color.base00
                            selectionColor: cfg.color.base0D
                        }

                        Repeater {
                            model: fullscreenFlick._blockRects
                            delegate: Rectangle {
                                required property var modelData
                                x: modelData.x; y: modelData.y
                                width: modelData.w; height: modelData.h
                                color: cfg.color.base0D; opacity: 0.4
                            }
                        }

                        // Cursor bar — always visible in fullscreen text view
                        Rectangle {
                            visible: root.fullscreenShowing && !root._detailIsImage && !root._detailLoading
                                     && fullscreenFlick._cursorRect.height > 0
                            x: fullscreenFlick._cursorRect.x
                            y: fullscreenFlick._cursorRect.y
                            width: 2
                            height: fullscreenFlick._cursorRect.height
                            color: cfg.color.base07
                            z: 10
                        }
                    }

                    Image {
                        id: fsImg
                        anchors.fill: parent
                        anchors.margins: 16
                        visible: root._detailIsImage && !root._detailLoading
                        fillMode: Image.PreserveAspectFit
                        smooth: true; mipmap: true; asynchronous: true
                        source: root._detailImgSource
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
                                    ShortcutRow { keys: "y";       action: "copy to clipboard" }
                                    ShortcutRow { keys: "v";       action: "visual select mode" }
                                    ShortcutRow { keys: "l";       action: "focus detail pane" }
                                    ShortcutRow { keys: "Enter";   action: "fullscreen detail" }
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
