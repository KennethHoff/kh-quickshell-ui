// Clipboard history detail panel.
//
// A thin shell around TextViewer. Owns the decode processes, refresh debounce,
// and stats bar. Delegates all text navigation and visual selection to TextViewer.
//
// The orchestrator sets `entry` whenever the list selection changes.
// ClipPreview debounces the decode and manages its own loading state.
//
// Properties in:
//   entry   — raw cliphist line (e.g. "123\t[[image/png]]")
//   focused — whether this panel has keyboard focus
//
// Properties out:
//   text          — decoded text content (empty while loading or image)
//   isImage       — true while showing an image entry
//   imageSource   — "file://..." for images; empty otherwise
//   hintText      — forwarded from TextViewer (changes by visual mode)
//   modeText      — forwarded from TextViewer ("CHR"/"LIN"/"BLK"/"")
//
// Signals:
//   exitFocus()                   — Tab or Esc in normal mode → orchestrator unfocuses
//   fullscreenRequested()         — Enter in normal mode
//   yankEntryRequested(rawLine)   — y in normal mode → orchestrator runs yank
//   yankTextRequested(text)       — y in visual mode (forwarded from TextViewer)
import QtQuick
import Quickshell.Io
import "./lib"

Item {
    id: preview

    // ── Config ────────────────────────────────────────────────────────────────
    NixConfig     { id: cfg }
    NixBins       { id: bin }
    CliphistEntry { id: clipEntry }

    // ── Properties in ─────────────────────────────────────────────────────────
    property string entry:   ""
    property bool   focused: false

    onEntryChanged: functionality.onEntryChanged()

    // ── Properties out ────────────────────────────────────────────────────────
    readonly property string text:        _text
    readonly property bool   isImage:     _isImage
    readonly property string imageSource: _imgSrc
    readonly property string hintText:    viewer.hintText
    readonly property string modeText:    viewer.modeText

    // ── Signals ───────────────────────────────────────────────────────────────
    signal exitFocus()
    signal fullscreenRequested()
    signal yankEntryRequested(string rawLine)
    signal yankTextRequested(string text)

    // ── Public API ─────────────────────────────────────────────────────────────
    // Returns true if the event was consumed.
    // viewer.handleKey handles all visual-mode keys and normal nav;
    // this layer intercepts only the context-boundary keys.
    function handleKey(event) {
        if (event.key === Qt.Key_Shift || event.key === Qt.Key_Control ||
            event.key === Qt.Key_Alt   || event.key === Qt.Key_Meta) return false

        if (viewer.handleKey(event)) return true

        // These are returned false by TextViewer in normal mode
        if (event.key === Qt.Key_Escape || event.key === Qt.Key_Tab || event.text === "q") {
            exitFocus(); return true
        }
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            fullscreenRequested(); return true
        }
        if (event.text === "y") {
            yankEntryRequested(entry); return true
        }
        return false
    }

    function handleIpcKey(k) {
        const lk = k.toLowerCase()
        if (lk === "escape" || lk === "esc" || lk === "tab") {
            exitFocus(); return true
        }
        if (lk === "enter" || lk === "return") {
            fullscreenRequested(); return true
        }
        if (lk === "y") {
            yankEntryRequested(entry); return true
        }
        if (lk === "v") {
            // Synthesise a "v" key event to toggle char visual mode
            return viewer.handleKey({ text: "v", key: Qt.Key_V, modifiers: 0 })
        }
        return false
    }

    // ── Private state ─────────────────────────────────────────────────────────
    property bool   _isImage: false
    property string _text:    ""
    property var    _lines:   []
    property bool   _loading: false
    property string _imgPath: ""
    property string _imgSrc:  ""
    property string _imgSize: ""

    // ── Impl ─────────────────────────────────────────────────────────────────
    QtObject {
        id: impl
        function refresh(): void {
            decodeProcess.running = false
            sizeProcess.running   = false
            preview._text    = ""
            preview._lines   = []
            preview._imgPath = ""
            preview._imgSrc  = ""
            preview._imgSize = ""

            if (preview.entry === "") {
                preview._isImage = false
                preview._loading = false
                viewer.reset()
                return
            }

            preview._isImage = clipEntry.entryPreview(preview.entry).startsWith("[[")
            preview._loading = true
            viewer.reset()

            const eid = clipEntry.entryId(preview.entry)
            preview._imgPath  = "/tmp/kh-cliphist-" + eid

            if (preview._isImage) {
                decodeProcess.command = [
                    bin.bash, "-c",
                    "[ -f \"$1\" ] || printf '%s\\n' \"$2\" | " + bin.cliphist + " decode > \"$1\"",
                    "--", preview._imgPath, preview.entry
                ]
            } else {
                decodeProcess.command = [
                    bin.bash, "-c",
                    "printf '%s\\n' \"$1\" | " + bin.cliphist + " decode",
                    "--", preview.entry
                ]
            }
            decodeProcess.running = true
        }
    }

    // ── Functionality ─────────────────────────────────────────────────────────
    QtObject {
        id: functionality
        // ui only
        function onEntryChanged(): void { refreshTimer.restart() }
        // ui only
        function onRefreshTimer(): void { impl.refresh() }
        // ui only
        function onDecodeRead(line: string): void { if (!preview._isImage) preview._lines.push(line) }
        // ui only
        function onDecodeExited(): void {
            if (preview._isImage) {
                preview._imgSrc = "file://" + preview._imgPath
                sizeProcess.command = [
                    bin.bash, "-c", "wc -c < \"$1\"", "--", preview._imgPath
                ]
                sizeProcess.running = true
            } else {
                preview._text    = preview._lines.join("\n")
                preview._lines   = []
                preview._loading = false
            }
        }
        // ui only
        function onSizeRead(line: string): void {
            const bytes = parseInt(line.trim())
            if (isNaN(bytes)) return
            if (bytes < 1024)         preview._imgSize = bytes + " B"
            else if (bytes < 1048576) preview._imgSize = (bytes / 1024).toFixed(1) + " KB"
            else                      preview._imgSize = (bytes / 1048576).toFixed(1) + " MB"
        }
        // ui only
        function onSizeExited(): void { preview._loading = false }
        // ui only
        function onYankTextRequested(t: string): void { preview.yankTextRequested(t) }
    }

    // ── Timers / Processes ────────────────────────────────────────────────────
    Timer {
        id: refreshTimer
        interval: 120
        repeat: false
        onTriggered: functionality.onRefreshTimer()
    }

    Process {
        id: decodeProcess
        stdout: SplitParser {
            onRead: (line) => functionality.onDecodeRead(line)
        }
        onExited: functionality.onDecodeExited()
    }

    Process {
        id: sizeProcess
        stdout: SplitParser {
            onRead: (line) => functionality.onSizeRead(line)
        }
        onExited: functionality.onSizeExited()
    }

    // ── UI ────────────────────────────────────────────────────────────────────
    // Header: type badge + entry preview text
    Item {
        id: previewHeader
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 36

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: preview._isImage ? "IMAGE" : "TEXT"
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
            text: preview.entry !== "" ? clipEntry.entryPreview(preview.entry) : ""
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

    // Stats bar: char/word/line counts (text) or dimensions + size (image)
    Item {
        id: statsBar
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
                if (preview._loading) return ""
                if (preview._isImage) {
                    const dim = viewer.imageNativeWidth > 0
                        ? viewer.imageNativeWidth + " \u00d7 " + viewer.imageNativeHeight + " px"
                        : ""
                    return dim + (dim && preview._imgSize ? "  \u00b7  " : "") + preview._imgSize
                }
                const t     = preview._text
                const chars = t.length
                const words = t.trim() ? t.trim().split(/\s+/).length : 0
                const lines = t ? t.split("\n").length : 0
                return chars + " chars  \u00b7  " + words + " words  \u00b7  " + lines + " lines"
            }
        }
    }

    // Main content via TextViewer
    TextViewer {
        id: viewer
        anchors.top: previewHeader.bottom
        anchors.bottom: statsBar.top
        anchors.left: parent.left
        anchors.right: parent.right

        text:        preview._text
        isImage:     preview._isImage
        imageSource: preview._imgSrc
        focused:     preview.focused
        loading:     preview._loading

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
