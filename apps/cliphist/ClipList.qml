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
    function flash(idx) {
        const item = list.itemAtIndex(idx)
        if (item) item.flash()
    }

    // ── Metadata stores ───────────────────────────────────────────────────────
    MetaStore { id: pinStore;  bash: bin.bash; appName: "kh-cliphist"; storeKey: "pins" }
    MetaStore { id: tsStore;   bash: bin.bash; appName: "kh-cliphist"; storeKey: "timestamps" }

    // Append `text` to the search field (IPC use only — not for key events).
    function typeText(text) {
        if (_mode === "insert") {
            searchField.text += text
            searchDebounce.stop()
            impl.runFilter()
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
            if (event.text === "y") impl.confirmDelete()
            else                    impl.cancelDelete()
            return true
        }
        if (_mode === "visual") return impl.handleVisualKey(event)
        if (_mode === "normal") return impl.handleNormalKey(event)
        return false
    }

    function handleIpcKey(k) {
        const lk = k.toLowerCase()
        if (_confirmingDelete) {
            if (lk === "y") impl.confirmDelete()
            else            impl.cancelDelete()
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
            if (_mode === "visual") impl.deleteVisualSelection()
            else impl.deleteSelected()
            return true
        }
        if (lk === "p") { impl.togglePin(); return true }
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

    // ── Impl ──────────────────────────────────────────────────────────────────
    QtObject {
        id: impl

        function entryId(rawLine): string {
            const t = rawLine.indexOf("\t")
            return t >= 0 ? rawLine.substring(0, t) : rawLine
        }

        // Phase 1 (normal mode): stage entry for deletion and ask for confirmation.
        function deleteSelected(): void {
            const rawLine = clipList.selectedEntry
            if (rawLine === "" || clipList._pendingDeleteLines.length > 0) return
            clipList._pendingDeleteLines     = [rawLine]
            clipList._pendingDeleteCursorIdx = Math.max(0, list.currentIndex - 1)
            clipList._pendingDeleteAnimLo    = list.currentIndex
            clipList._pendingDeleteAnimHi    = list.currentIndex
            clipList._confirmingDelete       = true
        }

        // Phase 1 (visual mode): stage range for deletion and ask for confirmation.
        function deleteVisualSelection(): void {
            if (clipList._pendingDeleteLines.length > 0) return
            const lo    = Math.min(clipList._visualAnchor, list.currentIndex)
            const hi    = Math.max(clipList._visualAnchor, list.currentIndex)
            const lines = clipList.filteredEntries.slice(lo, hi + 1)
            if (lines.length === 0) return
            clipList._pendingDeleteLines     = lines.slice()
            clipList._pendingDeleteCursorIdx = Math.max(0, lo - 1)
            clipList._pendingDeleteAnimLo    = lo
            clipList._pendingDeleteAnimHi    = hi
            clipList._confirmingDelete       = true
            enterNormalMode()
        }

        // Confirmed: start the fade-out animation; executePendingDelete fires after it.
        function confirmDelete(): void {
            clipList._confirmingDelete = false
            if (clipList._pendingDeleteLines.length === 0) return
            if (clipList._pendingDeleteAnimLo === clipList._pendingDeleteAnimHi) {
                const item = list.itemAtIndex(clipList._pendingDeleteAnimLo)
                if (item) item.startDeleteAnim()
            } else {
                for (let i = clipList._pendingDeleteAnimLo; i <= clipList._pendingDeleteAnimHi; i++) {
                    const item = list.itemAtIndex(i)
                    if (item) item.startDeleteAnim()
                }
            }
            deleteAnimTimer.restart()
        }

        // Cancelled: discard the staged deletion.
        function cancelDelete(): void {
            clipList._confirmingDelete       = false
            clipList._pendingDeleteLines     = []
            clipList._pendingDeleteCursorIdx = -1
            clipList._pendingDeleteAnimLo    = -1
            clipList._pendingDeleteAnimHi    = -1
        }

        // Toggle pin on the currently selected entry; cursor position stays stable.
        function togglePin(): void {
            const rawLine = clipList.selectedEntry
            if (rawLine === "") return
            const id = entryId(rawLine)
            if (id in pinStore.values)
                pinStore.remove(id)
            else
                pinStore.set(id, "1")
            const savedIdx = list.currentIndex
            runFilter()
            list.currentIndex = Math.min(savedIdx, clipList.filteredEntries.length - 1)
        }

        // Phase 2: called by deleteAnimTimer after the fade-out completes.
        function executePendingDelete(): void {
            const lines = clipList._pendingDeleteLines
            const targetIdx = clipList._pendingDeleteCursorIdx
            clipList._pendingDeleteLines     = []
            clipList._pendingDeleteCursorIdx = -1
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
            const newAll  = clipList.allEntries.filter(l => { const t = l.indexOf("\t"); return !idsToDelete.has(t >= 0 ? l.substring(0, t) : l) })
            const newProc = clipList._processed.filter(p => { const t = p.line.indexOf("\t"); return !idsToDelete.has(t >= 0 ? p.line.substring(0, t) : p.line) })
            clipList.allEntries = newAll
            clipList._processed = newProc
            const newIdx = {}
            for (let i = 0; i < newProc.length; i++) {
                const l   = newProc[i].line
                const t   = l.indexOf("\t")
                newIdx[t >= 0 ? l.substring(0, t) : l] = i
            }
            clipList._processedIdx = newIdx

            pinStore.removeMany(idsToDelete)

            runFilter()

            const newLen = clipList.filteredEntries.length
            if (newLen > 0) list.currentIndex = Math.min(targetIdx, newLen - 1)
        }

        function handleNormalKey(event): bool {
            if (event.text === "?") return false   // propagate → orchestrator opens help
            if (event.key === Qt.Key_Escape || event.text === "q") {
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
                if (clipList._pendingG) { gTimer.stop(); navTop(); clipList._pendingG = false }
                else                    { clipList._pendingG = true; gTimer.restart() }
                return true
            }
            if (event.key === Qt.Key_D && (event.modifiers & Qt.ControlModifier)) {
                navHalfDown(); return true
            }
            if (event.key === Qt.Key_D) {
                deleteSelected(); return true
            }
            if (event.key === Qt.Key_U && (event.modifiers & Qt.ControlModifier)) {
                navHalfUp(); return true
            }
            if (event.text === "y") {
                if (clipList.selectedEntry !== "") { flash(clipList.selectedIndex); yankEntryRequested(clipList.selectedEntry) }
                return true
            }
            if (event.text === "v") {
                enterVisualMode(); return true
            }
            if (event.text === "p") {
                togglePin(); return true
            }
            if (event.key === Qt.Key_Tab) {
                openDetail(); return true
            }
            if (event.key === Qt.Key_Slash) {
                enterInsertMode(); return true
            }
            return false
        }

        function handleVisualKey(event): bool {
            if (event.key === Qt.Key_Escape || event.text === "v" || event.text === "q") {
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
                if (clipList._pendingG) { gTimer.stop(); navTop(); clipList._pendingG = false }
                else                    { clipList._pendingG = true; gTimer.restart() }
                return true
            }
            if (event.key === Qt.Key_D && (event.modifiers & Qt.ControlModifier)) {
                navHalfDown(); return true
            }
            if (event.key === Qt.Key_D) {
                deleteVisualSelection(); return true
            }
            if (event.key === Qt.Key_U && (event.modifiers & Qt.ControlModifier)) {
                navHalfUp(); return true
            }
            return false
        }

        function runFilter(): void {
            const parsed  = searchParser.parseSearch(searchField.text)
            const pins    = pinStore.values
            const hasPins = Object.keys(pins).length > 0

            if (parsed.type === "all" && !parsed.needle) {
                if (!hasPins) {
                    clipList.filteredEntries = clipList.allEntries
                } else {
                    const pinned = [], rest = []
                    for (const e of clipList.allEntries)
                        (entryId(e) in pins ? pinned : rest).push(e)
                    clipList.filteredEntries = pinned.concat(rest)
                }
                return
            }

            const scored = []
            for (const e of clipList._processed) {
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
                    const pa = entryId(a.line) in pins
                    const pb = entryId(b.line) in pins
                    if (pa !== pb) return pa ? -1 : 1
                }
                return b.score - a.score
            })
            clipList.filteredEntries = scored.map(s => s.line)
        }
    }

    // ── Processes ─────────────────────────────────────────────────────────────
    Process {
        id: listProcess
        command: [bin.cliphist, "list"]
        stdout: SplitParser {
            onRead: (line) => functionality.onEntryRead(line)
        }
        onExited: functionality.onEntriesLoaded()
    }

    Process {
        id: fullTextDecodeProcess
        stdout: SplitParser {
            onRead: (line) => functionality.onFullTextRead(line)
        }
    }

    Timer {
        id: searchDebounce
        interval: 80
        repeat: false
        onTriggered: functionality.runFilter()
    }

    Timer {
        id: gTimer
        interval: 300
        repeat: false
        onTriggered: functionality.clearPendingG()
    }

    Timer {
        id: deleteAnimTimer
        interval: 220
        repeat: false
        onTriggered: functionality.executePendingDelete()
    }

    Process { id: deleteProcess }

    // ── Metadata store startup ────────────────────────────────────────────────
    Component.onCompleted: functionality.init()

    // ── Functionality ─────────────────────────────────────────────────────────
    QtObject {
        id: functionality

        // ui only — search field text change
        function onSearchTextChanged(): void { list.currentIndex = 0; searchDebounce.restart() }
        // ui only — Esc in insert mode
        function searchEscape(): void        { clipList._mode = "normal"; clipList.searchEscapePressed() }
        // ui only — Ctrl+* emacs bindings in search field
        function handleSearchCtrlKey(event): void {
            if (!(event.modifiers & Qt.ControlModifier)) return
            const pos = searchField.cursorPosition; const len = searchField.text.length
            if      (event.key === Qt.Key_A) { searchField.cursorPosition = 0 }
            else if (event.key === Qt.Key_E) { searchField.cursorPosition = len }
            else if (event.key === Qt.Key_F) { searchField.cursorPosition = Math.min(len, pos + 1) }
            else if (event.key === Qt.Key_B) { searchField.cursorPosition = Math.max(0, pos - 1) }
            else if (event.key === Qt.Key_D) { if (pos < len) searchField.remove(pos, pos + 1) }
            else if (event.key === Qt.Key_K) { if (pos < len) searchField.remove(pos, len) }
            else if (event.key === Qt.Key_W) {
                let i = pos
                while (i > 0 && searchField.text[i - 1] === " ") i--
                while (i > 0 && searchField.text[i - 1] !== " ") i--
                if (i !== pos) searchField.remove(i, pos)
            }
            else if (event.key === Qt.Key_U) { if (pos > 0) searchField.remove(0, pos) }
            else return
            event.accepted = true
        }
        // ui only — clamp list currentIndex on model count change
        function clampListIndex(): void { if (list.count > 0 && list.currentIndex < 0) list.currentIndex = 0 }
        // ui only — initialise metadata stores on startup
        function init(): void { pinStore.load(); tsStore.load() }
        // ui only — accumulate one line from the clipboard list process
        function onEntryRead(line: string): void { if (line !== "") clipList._buf.push(line) }
        // ui only — parse buffered entries and rebuild the processed list
        function onEntriesLoaded(): void {
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
            impl.runFilter()

            // Prune stale entries + first-seen timestamps for new ones.
            tsStore.pruneAndFill(idx, String(Math.floor(Date.now() / 1000)))
            // Prune pins that no longer exist in cliphist.
            pinStore.prune(idx)

            fullTextDecodeProcess.exec([bin.cliphistDecodeAll])
        }
        // ui only — handle one decoded full-text line
        function onFullTextRead(line: string): void {
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
        // ui only — run the filter (called by debounce timer)
        function runFilter(): void { impl.runFilter() }
        // ui only — clear the pending-G double-tap flag
        function clearPendingG(): void { clipList._pendingG = false }
        // ui only — commit the pending delete after animation
        function executePendingDelete(): void { impl.executePendingDelete() }
    }

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

                onTextChanged:        functionality.onSearchTextChanged()
                Keys.onEscapePressed: functionality.searchEscape()
                Keys.onPressed: (event) => functionality.handleSearchCtrlKey(event)
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

            onCountChanged: functionality.clampListIndex()

            Text {
                anchors.centerIn: parent
                visible: list.count === 0 && searchField.text.length > 0
                text: "No results"
                color: cfg.color.base03
                font.family: cfg.fontFamily
                font.pixelSize: cfg.fontSize
            }

            delegate: ClipDelegate {
                width:            list.width
                isCurrent:        list.currentIndex === index
                mode:             clipList._mode
                visualAnchor:     clipList._visualAnchor
                listCurrentIndex: list.currentIndex
                tsValues:         tsStore.values
                pinValues:        pinStore.values
            }
        }
    }
}
