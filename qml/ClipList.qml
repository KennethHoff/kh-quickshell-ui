// Clipboard history list view.
//
// Owns: allEntries, filteredEntries, decode processes, search field,
//       normal/visual mode, list navigation.
//
// The orchestrator holds keyboard focus on a dedicated handler and calls
// list.handleKey(event) in the "list active" branch of its dispatch chain.
// For insert mode, the orchestrator calls list.enterInsertMode(), which
// transfers focus to the internal search field.
//
// Properties out:
//   selectedEntry   — raw cliphist line at the current list position
//   selectedIndex   — currentIndex in the filtered list
//   mode            — "insert" | "normal" | "visual"
//   modeText        — "" | "NOR" | "VIS"
//   hintText        — footer hint for the current list state
//
// Signals:
//   openDetail()                    — Tab in normal mode
//   closeRequested()                — Esc in normal mode
//   yankEntryRequested(rawLine)     — y key (flash is triggered internally)
//   searchEscapePressed()           — Esc in insert mode; orchestrator reclaims focus
//
// handleKey(event) → bool
//   Processes normal / visual mode key events. Returns false for '?' so it
//   propagates to the orchestrator's help handler.
//
// handleIpcKey(k) → bool
//   IPC entry point for nav/mode/yank keys.
//
// enterInsertMode() / enterNormalMode() / enterVisualMode()
//   Mode transitions. enterInsertMode() transfers focus to the search field.
//   The orchestrator calls the others (and then forceActiveFocus on its own
//   key handler to reclaim focus).
import QtQuick
import Quickshell.Io
import "./lib"

Item {
    id: clipList

    // ── Config ────────────────────────────────────────────────────────────────
    NixConfig     { id: cfg }
    NixBins       { id: bin }
    CliphistEntry { id: clipEntry }
    FuzzyScore    { id: fuzzy }
    SearchParser  { id: searchParser }

    // ── Private state ─────────────────────────────────────────────────────────
    property var    allEntries:     []
    property var    filteredEntries: []
    property var    _buf:           []
    property var    _processed:     []
    property var    _processedIdx:  ({})
    property string _mode:              "insert"   // "insert" | "normal" | "visual"
    property bool   _pendingG:          false
    property int    _visualAnchor:      0
    property var    _pendingDeleteLines:     []
    property int    _pendingDeleteCursorIdx: -1
    property int    _pendingDeleteAnimLo:    -1
    property int    _pendingDeleteAnimHi:    -1
    property bool   _confirmingDelete:       false

    property var    _pins:     ({})   // {[id: string]: true} — pinned entry IDs
    property string _pinsFile: ""     // resolved once at startup
    property var    _pinsBuf:  []     // scratch buffer while loading the pins file

    // ── Properties out ────────────────────────────────────────────────────────
    readonly property string selectedEntry: {
        const idx = list.currentIndex
        const entries = filteredEntries
        return (idx >= 0 && idx < entries.length) ? entries[idx] : ""
    }
    readonly property int    selectedIndex: list.currentIndex
    readonly property string mode:     _mode
    readonly property string modeText: _mode === "visual" ? "VIS" : _mode === "normal" ? "NOR" : ""
    readonly property string hintText: {
        if (_confirmingDelete) {
            const n = _pendingDeleteLines.length
            return (n === 1 ? "Delete entry?" : "Delete " + n + " entries?") +
                   "  \u00b7  y confirm  \u00b7  Esc cancel"
        }
        if (_mode === "visual")
            return "j/k  select  \u00b7  d delete  \u00b7  v / Esc  normal mode"
        if (_mode === "normal")
            return "j/k navigate  \u00b7  v visual  \u00b7  y copy  \u00b7  d delete  \u00b7  p pin  \u00b7  Tab detail  \u00b7  / search  \u00b7  ? help  \u00b7  Esc close"
        return "Esc  normal mode  \u00b7  ?  help"
    }

    // ── Signals ───────────────────────────────────────────────────────────────
    signal openDetail()
    signal closeRequested()
    signal yankEntryRequested(string rawLine)
    // Esc pressed while in insert mode — orchestrator calls enterNormalMode()
    // then forceActiveFocus on its own key handler.
    signal searchEscapePressed()
    // Internal: drives flash animation on list delegates.
    signal flashRequested(int idx)
    // Internal: drives fade-out animation on the delegate being deleted.
    signal deleteAnimRequested(int idx)
    // Internal: drives fade-out on a range of delegates (visual delete).
    signal deleteRangeAnimRequested(int lo, int hi)

    // ── Public API ─────────────────────────────────────────────────────────────
    // Reset state — call when the window opens (before load).
    function reset() {
        allEntries      = []
        filteredEntries = []
        _buf            = []
        _processed      = []
        _processedIdx   = {}
        _mode           = "normal"   // per ROADMAP: opens in normal mode
        _pendingG                = false
        _confirmingDelete        = false
        _pendingDeleteLines      = []
        _pendingDeleteCursorIdx  = -1
        _pendingDeleteAnimLo     = -1
        _pendingDeleteAnimHi     = -1
        _visualAnchor            = 0
        searchField.text = ""
        list.currentIndex = 0
        searchDebounce.stop()
        fullTextDecodeProcess.running = false
        gTimer.stop()
        deleteAnimTimer.stop()
    }

    // Load entries — starts listProcess.
    function load() {
        listProcess.running = true
    }

    // Transfer keyboard focus to the search field.
    function enterInsertMode() {
        _mode = "insert"
        searchField.forceActiveFocus()
    }

    // Switch to normal mode; orchestrator must forceActiveFocus on its handler.
    function enterNormalMode() {
        _mode = "normal"
        _pendingG = false
    }

    // Switch to visual mode; orchestrator must forceActiveFocus on its handler.
    function enterVisualMode() {
        _visualAnchor = list.currentIndex
        _mode = "visual"
    }

    // Trigger the blink animation on the delegate at `idx`.
    function flash(idx) { flashRequested(idx) }

    // Phase 1 (normal mode): stage entry for deletion and ask for confirmation.
    function _deleteSelected() {
        const rawLine = selectedEntry
        if (rawLine === "" || _pendingDeleteLines.length > 0) return
        _pendingDeleteLines     = [rawLine]
        _pendingDeleteCursorIdx = Math.max(0, list.currentIndex - 1)
        _pendingDeleteAnimLo    = list.currentIndex
        _pendingDeleteAnimHi    = list.currentIndex
        _confirmingDelete       = true
    }

    // Phase 1 (visual mode): stage range for deletion and ask for confirmation.
    function _deleteVisualSelection() {
        if (_pendingDeleteLines.length > 0) return
        const lo    = Math.min(_visualAnchor, list.currentIndex)
        const hi    = Math.max(_visualAnchor, list.currentIndex)
        const lines = filteredEntries.slice(lo, hi + 1)
        if (lines.length === 0) return
        _pendingDeleteLines     = lines.slice()
        _pendingDeleteCursorIdx = Math.max(0, lo - 1)
        _pendingDeleteAnimLo    = lo
        _pendingDeleteAnimHi    = hi
        _confirmingDelete       = true
        enterNormalMode()
    }

    // Confirmed: start the fade-out animation; _executePendingDelete fires after it.
    function _confirmDelete() {
        _confirmingDelete = false
        if (_pendingDeleteLines.length === 0) return
        if (_pendingDeleteAnimLo === _pendingDeleteAnimHi)
            deleteAnimRequested(_pendingDeleteAnimLo)
        else
            deleteRangeAnimRequested(_pendingDeleteAnimLo, _pendingDeleteAnimHi)
        deleteAnimTimer.restart()
    }

    // Cancelled: discard the staged deletion.
    function _cancelDelete() {
        _confirmingDelete       = false
        _pendingDeleteLines     = []
        _pendingDeleteCursorIdx = -1
        _pendingDeleteAnimLo    = -1
        _pendingDeleteAnimHi    = -1
    }

    // ── Pinning ───────────────────────────────────────────────────────────────
    function _entryId(rawLine) {
        const t = rawLine.indexOf("\t")
        return t >= 0 ? rawLine.substring(0, t) : rawLine
    }

    // Toggle pin on the currently selected entry. Cursor follows the entry.
    function _togglePin() {
        const rawLine = selectedEntry
        if (rawLine === "") return
        const id = _entryId(rawLine)
        if (id in _pins) {
            const p = Object.assign({}, _pins)
            delete p[id]
            _pins = p
        } else {
            _pins = Object.assign({}, _pins, { [id]: true })
        }
        _writePins()
        const savedIdx = list.currentIndex
        _runFilter()
        list.currentIndex = Math.min(savedIdx, filteredEntries.length - 1)
    }

    // Persist the current pin set to disk.
    function _writePins() {
        if (!_pinsFile) return
        const ids = Object.keys(_pins)
        pinsWriteProcess.command = [bin.bash, "-c",
            'f="$1"; shift; printf "%s\\n" "$@" > "$f"', "--", _pinsFile].concat(ids)
        pinsWriteProcess.running = true
    }

    // Phase 2: called by deleteAnimTimer after the fade-out completes.
    function _executePendingDelete() {
        const lines = _pendingDeleteLines
        const targetIdx = _pendingDeleteCursorIdx
        _pendingDeleteLines     = []
        _pendingDeleteCursorIdx = -1
        if (lines.length === 0) return

        // Run cliphist delete for each line
        const args = [bin.bash, "-c",
            "for i in \"$@\"; do printf '%s\\n' \"$i\" | " + bin.cliphist + " delete; done",
            "--"]
        for (const l of lines) args.push(l)
        deleteProcess.command = args
        deleteProcess.running = true

        // Remove from local state in one pass
        const idsToDelete = new Set()
        for (const rawLine of lines) {
            const tab = rawLine.indexOf("\t")
            idsToDelete.add(tab >= 0 ? rawLine.substring(0, tab) : rawLine)
        }
        const newAll  = allEntries.filter(l => { const t = l.indexOf("\t"); return !idsToDelete.has(t >= 0 ? l.substring(0, t) : l) })
        const newProc = _processed.filter(p => { const t = p.line.indexOf("\t"); return !idsToDelete.has(t >= 0 ? p.line.substring(0, t) : p.line) })
        allEntries = newAll
        _processed = newProc
        const newIdx = {}
        for (let i = 0; i < newProc.length; i++) {
            const l   = newProc[i].line
            const t   = l.indexOf("\t")
            newIdx[t >= 0 ? l.substring(0, t) : l] = i
        }
        _processedIdx = newIdx

        // Remove deleted entries from pins if any were pinned
        let pinsChanged = false
        const newPins = Object.assign({}, _pins)
        for (const id of idsToDelete) {
            if (id in newPins) { delete newPins[id]; pinsChanged = true }
        }
        if (pinsChanged) { _pins = newPins; _writePins() }

        _runFilter()

        const newLen = filteredEntries.length
        if (newLen > 0) list.currentIndex = Math.min(targetIdx, newLen - 1)
    }

    // Append `text` to the search field (IPC use only — not for key events).
    function typeText(text) {
        if (_mode === "insert") {
            searchField.text += text
            searchDebounce.stop()
            _runFilter()
        }
    }

    // IPC nav helper (also used by orchestrator for IPC nav calls).
    function nav(dir) {
        if      (dir === "up")        navUp()
        else if (dir === "down")      navDown()
        else if (dir === "top")       navTop()
        else if (dir === "bottom")    navBottom()
        else if (dir === "half-down") navHalfDown()
        else if (dir === "half-up")   navHalfUp()
    }

    // Returns true if the event was consumed.
    // Does NOT consume '?' — caller handles help.
    // Only handles normal and visual mode; insert mode is handled natively by
    // the search field (which has focus in that mode).
    function handleKey(event) {
        if (event.key === Qt.Key_Shift || event.key === Qt.Key_Control ||
            event.key === Qt.Key_Alt   || event.key === Qt.Key_Meta) return false
        if (_confirmingDelete) {
            if (event.text === "y") _confirmDelete()
            else                    _cancelDelete()
            return true
        }
        if (_mode === "visual") return _handleVisualKey(event)
        if (_mode === "normal") return _handleNormalKey(event)
        return false
    }

    function handleIpcKey(k) {
        const lk = k.toLowerCase()
        if (_confirmingDelete) {
            if (lk === "y") _confirmDelete()
            else            _cancelDelete()
            return true
        }
        if (lk === "escape" || lk === "esc") {
            if (_mode !== "normal") { enterNormalMode(); return true }
            closeRequested(); return true
        }
        if (lk === "v") {
            if (_mode === "visual") { enterNormalMode(); return true }
            if (_mode === "normal") { enterVisualMode(); return true }
            return false
        }
        if (lk === "y") {
            if (selectedEntry !== "") { flash(selectedIndex); yankEntryRequested(selectedEntry) }
            return true
        }
        if (lk === "d") {
            if (_mode === "visual") _deleteVisualSelection()
            else _deleteSelected()
            return true
        }
        if (lk === "p") { _togglePin(); return true }
        if (lk === "tab") { openDetail(); return true }
        return false
    }

    // ── Navigation ────────────────────────────────────────────────────────────
    function navUp()       { if (list.currentIndex > 0) list.currentIndex-- }
    function navDown()     { if (list.currentIndex < list.count - 1) list.currentIndex++ }
    function navTop()      { list.currentIndex = 0 }
    function navBottom()   { list.currentIndex = Math.max(0, list.count - 1) }
    function navHalfDown() {
        const step = Math.max(1, Math.floor(list.height / 40 / 2))
        list.currentIndex = Math.min(list.count - 1, list.currentIndex + step)
    }
    function navHalfUp() {
        const step = Math.max(1, Math.floor(list.height / 40 / 2))
        list.currentIndex = Math.max(0, list.currentIndex - step)
    }

    // ── Private key handlers ──────────────────────────────────────────────────
    function _handleNormalKey(event) {
        if (event.text === "?") return false   // propagate → orchestrator opens help
        if (event.key === Qt.Key_Escape) {
            closeRequested(); return true
        }
        if (event.key === Qt.Key_J || event.key === Qt.Key_Down) {
            navDown(); return true
        }
        if (event.key === Qt.Key_K || event.key === Qt.Key_Up) {
            navUp(); return true
        }
        if (event.key === Qt.Key_G && (event.modifiers & Qt.ShiftModifier)) {
            navBottom(); return true
        }
        if (event.key === Qt.Key_G) {
            if (_pendingG) { gTimer.stop(); navTop(); _pendingG = false }
            else           { _pendingG = true; gTimer.restart() }
            return true
        }
        if (event.key === Qt.Key_D && (event.modifiers & Qt.ControlModifier)) {
            navHalfDown(); return true
        }
        if (event.key === Qt.Key_D) {
            _deleteSelected(); return true
        }
        if (event.key === Qt.Key_U && (event.modifiers & Qt.ControlModifier)) {
            navHalfUp(); return true
        }
        if (event.text === "y") {
            if (selectedEntry !== "") { flash(selectedIndex); yankEntryRequested(selectedEntry) }
            return true
        }
        if (event.text === "v") {
            enterVisualMode(); return true
        }
        if (event.text === "p") {
            _togglePin(); return true
        }
        if (event.key === Qt.Key_Tab) {
            openDetail(); return true
        }
        if (event.key === Qt.Key_Slash) {
            enterInsertMode(); return true
        }
        return false
    }

    function _handleVisualKey(event) {
        if (event.key === Qt.Key_Escape || event.text === "v") {
            enterNormalMode(); return true
        }
        if (event.key === Qt.Key_J || event.key === Qt.Key_Down) {
            navDown(); return true
        }
        if (event.key === Qt.Key_K || event.key === Qt.Key_Up) {
            navUp(); return true
        }
        if (event.key === Qt.Key_G && (event.modifiers & Qt.ShiftModifier)) {
            navBottom(); return true
        }
        if (event.key === Qt.Key_G) {
            if (_pendingG) { gTimer.stop(); navTop(); _pendingG = false }
            else           { _pendingG = true; gTimer.restart() }
            return true
        }
        if (event.key === Qt.Key_D && (event.modifiers & Qt.ControlModifier)) {
            navHalfDown(); return true
        }
        if (event.key === Qt.Key_D) {
            _deleteVisualSelection(); return true
        }
        if (event.key === Qt.Key_U && (event.modifiers & Qt.ControlModifier)) {
            navHalfUp(); return true
        }
        return false
    }

    // ── Filtering ─────────────────────────────────────────────────────────────
    function _runFilter() {
        const parsed  = searchParser.parseSearch(searchField.text)
        const hasPins = Object.keys(_pins).length > 0

        if (parsed.type === "all" && !parsed.needle) {
            if (!hasPins) {
                filteredEntries = allEntries
            } else {
                const pinned = [], rest = []
                for (const e of allEntries)
                    (_entryId(e) in _pins ? pinned : rest).push(e)
                filteredEntries = pinned.concat(rest)
            }
            return
        }

        const scored = []
        for (const e of _processed) {
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
        scored.sort((a, b) => {
            if (hasPins) {
                const pa = _entryId(a.line) in _pins
                const pb = _entryId(b.line) in _pins
                if (pa !== pb) return pa ? -1 : 1
            }
            return b.score - a.score
        })
        filteredEntries = scored.map(s => s.line)
    }

    // ── Processes ─────────────────────────────────────────────────────────────
    Process {
        id: listProcess
        command: [bin.cliphist, "list"]
        stdout: SplitParser {
            onRead: (line) => { if (line !== "") clipList._buf.push(line) }
        }
        onExited: {
            clipList.allEntries = clipList._buf.slice()
            clipList._buf = []
            const processed = [], idx = {}
            for (let i = 0; i < clipList.allEntries.length; i++) {
                const line    = clipList.allEntries[i]
                const tab     = line.indexOf("\t")
                const id      = tab >= 0 ? line.substring(0, tab) : line
                const preview = tab >= 0 ? line.substring(tab + 1) : line
                const isImage = preview.startsWith("[[")
                processed.push({ line, isImage,
                    haystack: isImage ? "" : preview.toLowerCase().replace(/\s+/g, "") })
                idx[id] = i
            }
            clipList._processed    = processed
            clipList._processedIdx = idx
            clipList._runFilter()
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
                    const i = clipList._processedIdx[id]
                    if (i !== undefined)
                        clipList._processed[i].haystack = fullText.toLowerCase().replace(/\s+/g, "")
                    searchDebounce.restart()
                } catch (_) {}
            }
        }
    }

    Timer {
        id: searchDebounce
        interval: 80
        repeat: false
        onTriggered: clipList._runFilter()
    }

    Timer {
        id: gTimer
        interval: 300
        repeat: false
        onTriggered: clipList._pendingG = false
    }

    Timer {
        id: deleteAnimTimer
        interval: 220
        repeat: false
        onTriggered: clipList._executePendingDelete()
    }

    Process { id: deleteProcess }

    // ── Pin persistence ───────────────────────────────────────────────────────
    Component.onCompleted: pinsPathProcess.running = true

    // Step 1: resolve $XDG_DATA_HOME/kh-cliphist/pins and create the directory.
    Process {
        id: pinsPathProcess
        command: [bin.bash, "-c",
            'f="${XDG_DATA_HOME:-$HOME/.local/share}/kh-cliphist/pins"' +
            '; mkdir -p "$(dirname "$f")"' +
            '; printf "%s\\n" "$f"']
        stdout: SplitParser {
            onRead: (line) => { if (line) clipList._pinsFile = line }
        }
        onExited: { if (clipList._pinsFile) pinsReadProcess.running = true }
    }

    // Step 2: read existing pins (one ID per line); silently skip if file absent.
    Process {
        id: pinsReadProcess
        command: [bin.bash, "-c", '[ -f "$1" ] && cat "$1" || true', "--", clipList._pinsFile]
        stdout: SplitParser {
            onRead: (line) => { if (line) clipList._pinsBuf.push(line) }
        }
        onExited: {
            const p = {}
            for (const id of clipList._pinsBuf) p[id] = true
            clipList._pins    = p
            clipList._pinsBuf = []
        }
    }

    // Step 3: write pins on demand (command is set dynamically in _writePins).
    Process { id: pinsWriteProcess }

    // ── UI ────────────────────────────────────────────────────────────────────
    Column {
        anchors.fill: parent
        anchors.margins: 8
        spacing: 4

        // Search bar ──────────────────────────────────────────────────────────
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
                visible: clipList._mode !== "insert"
                width: modeLabel.implicitWidth + 12
                height: 22
                radius: 4
                color: cfg.color.base02

                Text {
                    id: modeLabel
                    anchors.centerIn: parent
                    text: clipList.modeText
                    color: clipList._mode === "visual" ? cfg.color.base0E : cfg.color.base0D
                    font.family: cfg.fontFamily
                    font.pixelSize: cfg.fontSize - 3
                    font.bold: true
                }
            }

            TextInput {
                id: searchField
                anchors.fill: parent
                anchors.leftMargin: clipList._mode !== "insert" ? modeTag.width + 18 : 14
                anchors.rightMargin: 14
                color: cfg.color.base05
                font.family: cfg.fontFamily
                font.pixelSize: cfg.fontSize
                clip: true
                verticalAlignment: TextInput.AlignVCenter
                readOnly: clipList._mode !== "insert"

                Text {
                    anchors.fill: parent
                    visible: !searchField.text
                    text: "Search clipboard..."
                    color: cfg.color.base03
                    font.family: cfg.fontFamily
                    font.pixelSize: cfg.fontSize
                    verticalAlignment: Text.AlignVCenter
                }

                onTextChanged: { list.currentIndex = 0; searchDebounce.restart() }

                Keys.onEscapePressed: {
                    clipList._mode = "normal"
                    clipList.searchEscapePressed()
                }

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

        // Entry list ──────────────────────────────────────────────────────────
        ListView {
            id: list
            width: parent.width
            height: parent.height - searchBox.height - parent.spacing
            clip: true
            currentIndex: 0
            model: clipList.filteredEntries
            highlightMoveDuration: 0

            onCountChanged: if (count > 0 && currentIndex < 0) currentIndex = 0

            Text {
                anchors.centerIn: parent
                visible: list.count === 0 && searchField.text.length > 0
                text: "No results"
                color: cfg.color.base03
                font.family: cfg.fontFamily
                font.pixelSize: cfg.fontSize
            }

            delegate: Item {
                id: delegateRoot
                required property var modelData
                required property int index
                width: list.width
                height: isImage ? 64 : 40

                readonly property bool   isCurrent: list.currentIndex === index
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
                        if (clipList._mode === "visual") {
                            const lo = Math.min(clipList._visualAnchor, list.currentIndex)
                            const hi = Math.max(clipList._visualAnchor, list.currentIndex)
                            if (delegateRoot.index >= lo && delegateRoot.index <= hi)
                                return delegateRoot.isCurrent ? cfg.color.base03 : cfg.color.base02
                            return "transparent"
                        }
                        return delegateRoot.isCurrent ? cfg.color.base02 : "transparent"
                    }
                    radius: 6

                    // Pin indicator — 3 px coloured bar on the left edge
                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.margins: 3
                        width: 3
                        radius: 1
                        color: (clipList._pins, delegateRoot.entryId in clipList._pins)
                            ? cfg.color.base0A : "transparent"
                    }

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
                        anchors.leftMargin: 14
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
                            NumberAnimation {
                                target: flashOverlay; property: "opacity"
                                to: 0.55; duration: 60; easing.type: Easing.OutQuad
                            }
                            NumberAnimation {
                                target: flashOverlay; property: "opacity"
                                to: 0; duration: 140; easing.type: Easing.InQuad
                            }
                        }
                    }

                    Connections {
                        target: clipList
                        function onFlashRequested(idx) {
                            if (idx === delegateRoot.index) blinkAnim.restart()
                        }
                        function onDeleteAnimRequested(idx) {
                            if (idx === delegateRoot.index) fadeOutAnim.start()
                        }
                        function onDeleteRangeAnimRequested(lo, hi) {
                            if (delegateRoot.index >= lo && delegateRoot.index <= hi) fadeOutAnim.start()
                        }
                    }
                }

                NumberAnimation {
                    id: fadeOutAnim
                    target: delegateRoot
                    property: "opacity"
                    to: 0
                    duration: 200
                    easing.type: Easing.InQuad
                }
            }
        }
    }
}
