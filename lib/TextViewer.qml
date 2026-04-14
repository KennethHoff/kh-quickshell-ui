// Reusable scrollable text/image viewer with vim-style cursor navigation and
// char / line / block visual selection.
//
// The caller is responsible for styling: pass textColor, selectionColor, etc.
// from whatever config mechanism the parent module uses.
//
// Key handling: call handleKey(event) from the parent's Keys.onPressed.
// Returns true if the event was consumed, false to let the parent handle it.
// Events returned as false: y (normal mode), Esc, Enter, Tab — all context-
// specific bindings the parent layer owns.
//
// Signals:
//   yankTextRequested(string text)  — emit when the user yanks in visual mode
//
// Example:
//   TextViewer {
//       id: viewer
//       text: someText
//       focused: detailFocused
//       textColor: cfg.color.base05
//       selectionColor: cfg.color.base0D
//       selectionTextColor: cfg.color.base00
//       cursorColor: cfg.color.base07
//       fontFamily: cfg.fontFamily
//       fontSize: cfg.fontSize
//       onYankTextRequested: (t) => copyToClipboard(t)
//   }
//   Keys.onPressed: (e) => { if (!viewer.handleKey(e)) { /* parent bindings */ } }
import QtQuick

Item {
    id: viewer

    // ── Style ────────────────────────────────────────────────────────────────
    property color  textColor:          "#cdd6f4"
    property color  selectionColor:     "#89b4fa"
    property color  selectionTextColor: "#1e1e2e"
    property color  cursorColor:        "#b4befe"
    property color  dimColor:           "#45475a"
    property string fontFamily:         "monospace"
    property int    fontSize:           14

    // Padding — override to match surrounding layout
    property int hPad: 12
    property int vPad: 10

    // ── Content inputs ────────────────────────────────────────────────────────
    property string text:        ""
    property bool   isImage:     false
    property string imageSource: ""
    property bool   focused:     false
    property bool   loading:     false

    // ── Outputs ──────────────────────────────────────────────────────────────
    readonly property int imageNativeWidth:  img.implicitWidth
    readonly property int imageNativeHeight: img.implicitHeight

    // Text for the mode badge (CHR / LIN / BLK / "")
    readonly property string modeText: {
        if (_visualMode === "char")  return "CHR"
        if (_visualMode === "line")  return "LIN"
        if (_visualMode === "block") return "BLK"
        return ""
    }

    // Hint covering only what TextViewer itself handles; parent adds surrounding
    // context (Esc back, Tab, Enter fullscreen, y in normal mode, etc.)
    readonly property string hintText: {
        if (_visualMode === "char")
            return "v/Esc exit  \u00b7  hjkl extend  \u00b7  o swap  \u00b7  V line  \u00b7  Ctrl+V block  \u00b7  y copy"
        if (_visualMode === "line")
            return "V/Esc exit  \u00b7  j/k extend  \u00b7  o swap  \u00b7  v char  \u00b7  Ctrl+V block  \u00b7  y copy"
        if (_visualMode === "block")
            return "Ctrl+V/Esc exit  \u00b7  j/k/h/l move  \u00b7  o diag  \u00b7  O col  \u00b7  v char  \u00b7  y copy"
        return "hjkl cursor  \u00b7  w/b/e word  \u00b7  0/$  line  \u00b7  v/V/Ctrl+V visual"
    }

    // ── Signals ──────────────────────────────────────────────────────────────
    signal yankTextRequested(string text)

    // ── Public API ────────────────────────────────────────────────────────────
    // Returns true if the key was consumed.
    // Does NOT consume: y (normal mode), Esc, Enter, Tab — parent handles those.
    function handleKey(event) {
        if (event.key === Qt.Key_Shift || event.key === Qt.Key_Control ||
            event.key === Qt.Key_Alt   || event.key === Qt.Key_Meta) return false
        if (isImage || loading) return false

        if (_visualMode !== "") return impl.handleVisualKey(event)

        // ── Normal cursor movement ─────────────────────────────────────────
        if (event.key === Qt.Key_J || event.key === Qt.Key_Down) {
            const r  = edit.positionToRectangle(edit.cursorPosition)
            const np = edit.positionAt(r.x, r.y + r.height + 1)
            if (np !== edit.cursorPosition) { edit.select(np, np); impl.scrollIntoView(np) }
            return true
        }
        if (event.key === Qt.Key_K || event.key === Qt.Key_Up) {
            const r  = edit.positionToRectangle(edit.cursorPosition)
            const np = edit.positionAt(r.x, r.y - 1)
            if (np !== edit.cursorPosition) { edit.select(np, np); impl.scrollIntoView(np) }
            return true
        }
        if (event.key === Qt.Key_H || event.key === Qt.Key_Left) {
            const cp = edit.cursorPosition
            if (cp > 0) { edit.select(cp - 1, cp - 1); impl.scrollIntoView(cp - 1) }
            return true
        }
        if (event.key === Qt.Key_L || event.key === Qt.Key_Right) {
            const cp = edit.cursorPosition
            if (cp < edit.text.length) { edit.select(cp + 1, cp + 1); impl.scrollIntoView(cp + 1) }
            return true
        }

        // ── Word motions ──────────────────────────────────────────────────
        if (event.text === "w") {
            const np = impl.wordForward(edit.cursorPosition)
            edit.select(np, np); impl.scrollIntoView(np); return true
        }
        if (event.text === "W") {
            const np = impl.WORDForward(edit.cursorPosition)
            edit.select(np, np); impl.scrollIntoView(np); return true
        }
        if (event.text === "b") {
            const np = impl.wordBackward(edit.cursorPosition)
            edit.select(np, np); impl.scrollIntoView(np); return true
        }
        if (event.text === "B") {
            const np = impl.WORDBackward(edit.cursorPosition)
            edit.select(np, np); impl.scrollIntoView(np); return true
        }
        if (event.text === "e") {
            const np = impl.wordEnd(edit.cursorPosition)
            edit.select(np, np); impl.scrollIntoView(np); return true
        }
        if (event.text === "E") {
            const np = impl.WORDEnd(edit.cursorPosition)
            edit.select(np, np); impl.scrollIntoView(np); return true
        }
        if (event.text === "0") {
            const np = impl.posLineStart(edit.cursorPosition)
            edit.select(np, np); impl.scrollIntoView(np); return true
        }
        if (event.text === "$") {
            const np = impl.posLineEnd(edit.cursorPosition)
            edit.select(np, np); impl.scrollIntoView(np); return true
        }
        if (event.text === "^") {
            const np = impl.posFirstNonBlank(edit.cursorPosition)
            edit.select(np, np); impl.scrollIntoView(np); return true
        }

        // ── Enter visual ──────────────────────────────────────────────────
        if (event.text === "v") { impl.enterVisual("char");  return true }
        if (event.text === "V") { impl.enterVisual("line");  return true }
        if (event.key === Qt.Key_V && (event.modifiers & Qt.ControlModifier)) {
            impl.enterVisual("block"); return true
        }

        // ── Scroll / jump ─────────────────────────────────────────────────
        const halfPg = Math.max(fontSize + 6, Math.floor(flick.height / 2))
        if (event.key === Qt.Key_D && (event.modifiers & Qt.ControlModifier)) {
            flick.contentY = Math.min(Math.max(0, flick.contentHeight - flick.height),
                                      flick.contentY + halfPg)
            return true
        }
        if (event.key === Qt.Key_U && (event.modifiers & Qt.ControlModifier)) {
            flick.contentY = Math.max(0, flick.contentY - halfPg)
            return true
        }
        if (event.key === Qt.Key_G && (event.modifiers & Qt.ShiftModifier)) {
            flick.contentY = Math.max(0, flick.contentHeight - flick.height); return true
        }
        if (event.key === Qt.Key_G) {
            if (_pendingGg) { ggTimer.stop(); flick.contentY = 0; _pendingGg = false }
            else            { _pendingGg = true; ggTimer.restart() }
            return true
        }

        return false   // y, Esc, Enter, Tab — caller's responsibility
    }

    // IPC-friendly key handler — accepts a string key name and delegates to
    // handleKey via a synthetic event object. Covers all keys handleKey handles
    // plus ctrl+d / ctrl+u / G / gg for scroll/jump.
    function handleIpcKey(k: string): bool {
        const lk = k.toLowerCase()
        const ctrl = lk.startsWith("ctrl+")
        const bare = ctrl ? lk.slice(5) : lk
        const keyMap = {
            "j": Qt.Key_J,  "down":  Qt.Key_Down,
            "k": Qt.Key_K,  "up":    Qt.Key_Up,
            "h": Qt.Key_H,  "left":  Qt.Key_Left,
            "l": Qt.Key_L,  "right": Qt.Key_Right,
            "d": Qt.Key_D,  "u":     Qt.Key_U,
            "g": Qt.Key_G,  "v":     Qt.Key_V,
        }
        const qtKey = keyMap[bare] ?? 0
        const mods  = ctrl ? Qt.ControlModifier
                    : (k === "G" || k === "V") ? Qt.ShiftModifier
                    : Qt.NoModifier
        return handleKey({ key: qtKey, text: k === k.toUpperCase() ? k : lk, modifiers: mods })
    }

    // Reset to top with no selection. Call when the displayed content changes.
    function reset() {
        _visualMode = ""
        _pendingGg  = false
        ggTimer.stop()
        flick.contentY = 0
        if (!isImage) edit.select(0, 0)
    }

    // ── Private visual state ──────────────────────────────────────────────────
    property string _visualMode:      ""
    property int    _visualAnchorPos: 0
    property int    _visualAnchorRow: 0
    property int    _visualAnchorCol: 0
    property int    _visualCurRow:    0
    property int    _visualCurCol:    0
    property bool   _pendingGg:       false

    QtObject {
        id: functionality
        // ui only
        function clearPendingGg(): void { viewer._pendingGg = false }
    }

    Timer { id: ggTimer; interval: 300; onTriggered: functionality.clearPendingGg() }

    // ── Impl ──────────────────────────────────────────────────────────────────
    QtObject {
        id: impl

        function logicalLineAt(pos): int {
            const t = edit.text; let n = 0
            for (let i = 0; i < pos && i < t.length; i++) if (t[i] === '\n') n++
            return n
        }
        function lineStartAt(row): int {
            const t = edit.text; let n = 0, i = 0
            while (i < t.length && n < row) { if (t[i] === '\n') n++; i++ }
            return i
        }
        function lineEndAt(row): int {
            const t = edit.text; let i = lineStartAt(row)
            while (i < t.length && t[i] !== '\n') i++
            return i
        }
        function lineCount(): int {
            const t = edit.text; if (!t) return 1
            let n = 1
            for (let i = 0; i < t.length; i++) if (t[i] === '\n') n++
            return n
        }

        function isWordChar(ch): bool { return /\w/.test(ch) }
        function isSpace(ch): bool    { return ch === ' ' || ch === '\t' || ch === '\n' || ch === '\r' }

        function posLineStart(pos): int {
            const t = edit.text
            while (pos > 0 && t[pos - 1] !== '\n') pos--
            return pos
        }
        function posLineEnd(pos): int {
            const t = edit.text; const n = t.length
            while (pos < n && t[pos] !== '\n') pos++
            return pos
        }
        function posFirstNonBlank(pos): int {
            pos = posLineStart(pos)
            const t = edit.text; const n = t.length
            while (pos < n && t[pos] !== '\n' && (t[pos] === ' ' || t[pos] === '\t')) pos++
            return pos
        }

        // w — forward to start of next word
        function wordForward(pos): int {
            const t = edit.text; const n = t.length
            if (pos >= n) return pos
            const c = t[pos]
            if      (isWordChar(c))  while (pos < n && isWordChar(t[pos]))                      pos++
            else if (!isSpace(c))    while (pos < n && !isWordChar(t[pos]) && !isSpace(t[pos])) pos++
            while (pos < n && isSpace(t[pos])) pos++
            return pos
        }
        // W — forward to start of next WORD (whitespace-delimited)
        function WORDForward(pos): int {
            const t = edit.text; const n = t.length
            if (pos >= n) return pos
            while (pos < n && !isSpace(t[pos])) pos++
            while (pos < n &&  isSpace(t[pos])) pos++
            return pos
        }
        // b — backward to start of current/previous word
        function wordBackward(pos): int {
            const t = edit.text
            if (pos <= 0) return 0
            pos--
            while (pos > 0 && isSpace(t[pos])) pos--
            if (isWordChar(t[pos]))
                while (pos > 0 && isWordChar(t[pos - 1]))                        pos--
            else
                while (pos > 0 && !isWordChar(t[pos - 1]) && !isSpace(t[pos - 1])) pos--
            return pos
        }
        // B — backward to start of current/previous WORD
        function WORDBackward(pos): int {
            const t = edit.text
            if (pos <= 0) return 0
            pos--
            while (pos > 0 && isSpace(t[pos]))       pos--
            while (pos > 0 && !isSpace(t[pos - 1]))  pos--
            return pos
        }
        // e — forward to end of current/next word
        function wordEnd(pos): int {
            const t = edit.text; const n = t.length
            if (pos >= n - 1) return n > 0 ? n - 1 : 0
            pos++
            while (pos < n && isSpace(t[pos])) pos++
            if (pos >= n) return n - 1
            if (isWordChar(t[pos]))
                while (pos + 1 < n && isWordChar(t[pos + 1]))                        pos++
            else
                while (pos + 1 < n && !isWordChar(t[pos + 1]) && !isSpace(t[pos + 1])) pos++
            return pos
        }
        // E — forward to end of current/next WORD
        function WORDEnd(pos): int {
            const t = edit.text; const n = t.length
            if (pos >= n - 1) return n > 0 ? n - 1 : 0
            pos++
            while (pos < n && isSpace(t[pos]))           pos++
            if (pos >= n) return n - 1
            while (pos + 1 < n && !isSpace(t[pos + 1])) pos++
            return pos
        }

        function scrollIntoView(pos): void {
            const r = edit.positionToRectangle(pos)
            if (r.y + r.height > flick.contentY + flick.height)
                flick.contentY = Math.min(Math.max(0, flick.contentHeight - flick.height),
                                          r.y + r.height - flick.height)
            else if (r.y < flick.contentY)
                flick.contentY = Math.max(0, r.y)
        }
        function applyLineSelection(): void {
            const lo = Math.min(viewer._visualAnchorRow, viewer._visualCurRow)
            const hi = Math.max(viewer._visualAnchorRow, viewer._visualCurRow)
            const s  = lineStartAt(lo), e = lineEndAt(hi)
            if (viewer._visualCurRow >= viewer._visualAnchorRow) edit.select(s, e)
            else                                                  edit.select(e, s)
        }
        function enterVisual(mode: string): void {
            const sp = edit.cursorPosition
            viewer._visualMode = mode
            if (mode === "char") {
                viewer._visualAnchorPos = sp; edit.select(sp, sp)
            } else if (mode === "line") {
                const row = logicalLineAt(sp)
                viewer._visualAnchorRow = row; viewer._visualCurRow = row
                viewer._visualAnchorPos = lineStartAt(row)
                applyLineSelection()
            } else if (mode === "block") {
                const row = logicalLineAt(sp)
                const col = sp - lineStartAt(row)
                viewer._visualAnchorRow = row; viewer._visualAnchorCol = col
                viewer._visualCurRow    = row; viewer._visualCurCol    = col
                viewer._visualAnchorPos = sp
                edit.select(0, 0)
            }
        }
        function handleVisualKey(event): bool {
            // ── Exit / mode-switch ─────────────────────────────────────────────
            if (event.key === Qt.Key_Escape || event.text === "q") {
                const cp = edit.cursorPosition; viewer._visualMode = ""; edit.select(cp, cp); return true
            }
            if (event.text === "v") {
                if (viewer._visualMode === "char") {
                    const cp = edit.cursorPosition; viewer._visualMode = ""; edit.select(cp, cp)
                } else {
                    let cp = edit.cursorPosition
                    if (viewer._visualMode === "block")
                        cp = Math.min(lineStartAt(viewer._visualCurRow) + viewer._visualCurCol,
                                      lineEndAt(viewer._visualCurRow))
                    viewer._visualMode = "char"; viewer._visualAnchorPos = cp; edit.select(cp, cp)
                }
                return true
            }
            if (event.text === "V") {
                if (viewer._visualMode === "line") {
                    const cp = edit.cursorPosition; viewer._visualMode = ""; edit.select(cp, cp)
                } else {
                    const cp = edit.cursorPosition
                    const cur = logicalLineAt(cp), anc = logicalLineAt(viewer._visualAnchorPos)
                    viewer._visualMode = "line"
                    viewer._visualAnchorRow = anc; viewer._visualCurRow = cur
                    viewer._visualAnchorPos = lineStartAt(anc)
                    applyLineSelection()
                }
                return true
            }
            if (event.key === Qt.Key_V && (event.modifiers & Qt.ControlModifier)) {
                if (viewer._visualMode === "block") {
                    viewer._visualMode = ""
                } else {
                    const cp   = edit.cursorPosition
                    const cur  = logicalLineAt(cp)
                    const ccol = cp - lineStartAt(cur)
                    const anc  = logicalLineAt(viewer._visualAnchorPos)
                    const acol = viewer._visualAnchorPos - lineStartAt(anc)
                    viewer._visualMode      = "block"
                    viewer._visualAnchorRow = anc; viewer._visualAnchorCol = acol
                    viewer._visualCurRow    = cur; viewer._visualCurCol    = ccol
                    viewer._visualAnchorPos = lineStartAt(anc) + acol
                    edit.select(0, 0)
                }
                return true
            }

            // ── Char mode ──────────────────────────────────────────────────────
            if (viewer._visualMode === "char") {
                if (event.text === "y") {
                    const sel = edit.selectedText
                    if (sel) viewer.yankTextRequested(sel)
                    viewer._visualMode = ""; edit.select(0, 0); return true
                }
                if (event.text === "o" || event.text === "O") {
                    const oldAnc = viewer._visualAnchorPos, oldCur = edit.cursorPosition
                    viewer._visualAnchorPos = oldCur; edit.select(oldCur, oldAnc); return true
                }
                if (event.key === Qt.Key_J || event.key === Qt.Key_Down) {
                    const r  = edit.positionToRectangle(edit.cursorPosition)
                    const np = edit.positionAt(r.x, r.y + r.height + 1)
                    if (np !== edit.cursorPosition) {
                        edit.moveCursorSelection(np, TextEdit.SelectCharacters); scrollIntoView(np)
                    }
                    return true
                }
                if (event.key === Qt.Key_K || event.key === Qt.Key_Up) {
                    const r  = edit.positionToRectangle(edit.cursorPosition)
                    const np = edit.positionAt(r.x, r.y - 1)
                    if (np !== edit.cursorPosition) {
                        edit.moveCursorSelection(np, TextEdit.SelectCharacters); scrollIntoView(np)
                    }
                    return true
                }
                if (event.key === Qt.Key_H || event.key === Qt.Key_Left) {
                    const np = Math.max(0, edit.cursorPosition - 1)
                    if (np !== edit.cursorPosition) {
                        edit.moveCursorSelection(np, TextEdit.SelectCharacters); scrollIntoView(np)
                    }
                    return true
                }
                if (event.key === Qt.Key_L || event.key === Qt.Key_Right) {
                    const np = Math.min(edit.text.length, edit.cursorPosition + 1)
                    if (np !== edit.cursorPosition) {
                        edit.moveCursorSelection(np, TextEdit.SelectCharacters); scrollIntoView(np)
                    }
                    return true
                }
                // ── Word motions (extend selection) ────────────────────────────
                {
                    let np = -1
                    if      (event.text === "w") np = wordForward(edit.cursorPosition)
                    else if (event.text === "W") np = WORDForward(edit.cursorPosition)
                    else if (event.text === "b") np = wordBackward(edit.cursorPosition)
                    else if (event.text === "B") np = WORDBackward(edit.cursorPosition)
                    else if (event.text === "e") np = wordEnd(edit.cursorPosition)
                    else if (event.text === "E") np = WORDEnd(edit.cursorPosition)
                    else if (event.text === "0") np = posLineStart(edit.cursorPosition)
                    else if (event.text === "$") np = posLineEnd(edit.cursorPosition)
                    else if (event.text === "^") np = posFirstNonBlank(edit.cursorPosition)
                    if (np >= 0 && np !== edit.cursorPosition) {
                        edit.moveCursorSelection(np, TextEdit.SelectCharacters)
                        scrollIntoView(np)
                    }
                    if (np >= 0) return true
                }
                return false
            }

            // ── Line mode ──────────────────────────────────────────────────────
            if (viewer._visualMode === "line") {
                if (event.text === "y") {
                    const lo = Math.min(viewer._visualAnchorRow, viewer._visualCurRow)
                    const hi = Math.max(viewer._visualAnchorRow, viewer._visualCurRow)
                    viewer.yankTextRequested(edit.text.substring(lineStartAt(lo), lineEndAt(hi)))
                    viewer._visualMode = ""; edit.select(0, 0); return true
                }
                if (event.text === "o" || event.text === "O") {
                    const tmp = viewer._visualAnchorRow
                    viewer._visualAnchorRow = viewer._visualCurRow; viewer._visualCurRow = tmp
                    applyLineSelection(); scrollIntoView(edit.cursorPosition); return true
                }
                if (event.key === Qt.Key_J || event.key === Qt.Key_Down) {
                    if (viewer._visualCurRow < lineCount() - 1) {
                        viewer._visualCurRow++; applyLineSelection(); scrollIntoView(edit.cursorPosition)
                    }
                    return true
                }
                if (event.key === Qt.Key_K || event.key === Qt.Key_Up) {
                    if (viewer._visualCurRow > 0) {
                        viewer._visualCurRow--; applyLineSelection(); scrollIntoView(edit.cursorPosition)
                    }
                    return true
                }
                return false
            }

            // ── Block mode ─────────────────────────────────────────────────────
            if (viewer._visualMode === "block") {
                if (event.text === "y") {
                    const lo    = Math.min(viewer._visualAnchorRow, viewer._visualCurRow)
                    const hi    = Math.max(viewer._visualAnchorRow, viewer._visualCurRow)
                    const loCol = Math.min(viewer._visualAnchorCol, viewer._visualCurCol)
                    const hiCol = Math.max(viewer._visualAnchorCol, viewer._visualCurCol)
                    const lines = []
                    for (let row = lo; row <= hi; row++) {
                        const ls = lineStartAt(row), le = lineEndAt(row)
                        lines.push(edit.text.substring(ls, le).substring(loCol, hiCol + 1))
                    }
                    viewer.yankTextRequested(lines.join("\n"))
                    viewer._visualMode = ""; return true
                }
                if (event.text === "o") {
                    const tr = viewer._visualAnchorRow, tc = viewer._visualAnchorCol
                    viewer._visualAnchorRow = viewer._visualCurRow; viewer._visualAnchorCol = viewer._visualCurCol
                    viewer._visualCurRow = tr; viewer._visualCurCol = tc; return true
                }
                if (event.text === "O") {
                    const tc = viewer._visualAnchorCol
                    viewer._visualAnchorCol = viewer._visualCurCol; viewer._visualCurCol = tc; return true
                }
                if (event.key === Qt.Key_J || event.key === Qt.Key_Down) {
                    if (viewer._visualCurRow < lineCount() - 1) viewer._visualCurRow++; return true
                }
                if (event.key === Qt.Key_K || event.key === Qt.Key_Up) {
                    if (viewer._visualCurRow > 0) viewer._visualCurRow--; return true
                }
                if (event.key === Qt.Key_L || event.key === Qt.Key_Right) {
                    viewer._visualCurCol++; return true
                }
                if (event.key === Qt.Key_H || event.key === Qt.Key_Left) {
                    if (viewer._visualCurCol > 0) viewer._visualCurCol--; return true
                }
                return false
            }

            return false
        }
    }

    // ── UI ────────────────────────────────────────────────────────────────────
    Text {
        anchors.centerIn: parent
        visible: loading
        text: "Loading..."
        color: dimColor
        font.family: fontFamily
        font.pixelSize: fontSize
    }

    Flickable {
        id: flick
        anchors.fill: parent
        visible: !isImage && !loading
        contentHeight: edit.implicitHeight
        contentWidth: width
        clip: true

        // Block-visual highlight rects (computed from visual state + TextEdit geometry)
        property var _blockRects: {
            if (_visualMode !== "block" || !focused || !viewer.text) return []
            const lo    = Math.min(_visualAnchorRow, _visualCurRow)
            const hi    = Math.max(_visualAnchorRow, _visualCurRow)
            const loCol = Math.min(_visualAnchorCol, _visualCurCol)
            const hiCol = Math.max(_visualAnchorCol, _visualCurCol)
            const rects = []
            for (let row = lo; row <= hi; row++) {
                const ls = impl.lineStartAt(row), le = impl.lineEndAt(row)
                const sp = ls + loCol <= le ? ls + loCol : le
                const ep = ls + hiCol <= le ? ls + hiCol : (le > 0 ? le - 1 : le)
                const sr = edit.positionToRectangle(sp)
                const er = ep >= sp ? edit.positionToRectangle(ep) : sr
                rects.push({ x: sr.x, y: sr.y, w: Math.max(4, er.x + er.width - sr.x), h: sr.height })
            }
            return rects
        }

        // Cursor rect — always tracked while focused on text
        property rect _cursorRect: {
            if (!focused || isImage || loading) return Qt.rect(0, 0, 0, 0)
            let pos
            if (_visualMode === "block") {
                const ls = impl.lineStartAt(_visualCurRow)
                pos = Math.min(ls + _visualCurCol, impl.lineEndAt(_visualCurRow))
            } else {
                pos = edit.cursorPosition
            }
            return edit.positionToRectangle(pos)
        }

        TextEdit {
            id: edit
            width: parent.width
            leftPadding: hPad; rightPadding: hPad
            topPadding:  vPad; bottomPadding: vPad
            text: viewer.text
            color: textColor
            font.family: fontFamily
            font.pixelSize: fontSize
            wrapMode: TextEdit.Wrap
            readOnly: true
            selectByMouse: false
            selectByKeyboard: false
            cursorVisible: false
            selectedTextColor: selectionTextColor
            selectionColor: selectionColor
        }

        Repeater {
            model: flick._blockRects
            delegate: Rectangle {
                required property var modelData
                x: modelData.x; y: modelData.y
                width: modelData.w; height: modelData.h
                color: selectionColor; opacity: 0.4
            }
        }

        // Cursor bar — visible whenever focused on text (not only in visual mode)
        Rectangle {
            visible: focused && !isImage && !loading && flick._cursorRect.height > 0
            x: flick._cursorRect.x
            y: flick._cursorRect.y
            width: 2
            height: flick._cursorRect.height
            color: cursorColor
            z: 10
        }
    }

    Image {
        id: img
        anchors.fill: parent
        visible: isImage && !loading
        source: imageSource
        fillMode: Image.PreserveAspectFit
        smooth: true; mipmap: true; asynchronous: true
    }
}
