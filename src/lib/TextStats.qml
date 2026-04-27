// Text and image stats helpers for the kh-cliphist detail panel.
// Mirrors the inline expressions in kh-cliphist.nix lines 671-717.
import QtQuick

QtObject {
    readonly property string _sep: "  \u00b7  "

    function wordCount(text) {
        return text.trim() === "" ? 0 : text.trim().split(/\s+/).length
    }

    function lineCount(text) {
        return text.split("\n").length
    }

    // Builds the stats footer for a text entry.
    // showFullscreenHint mirrors (root.view === "detail").
    function buildTextStats(text, showFullscreenHint) {
        const chars = text.length
        const words = wordCount(text)
        const lines = lineCount(text)
        const parts = [
            chars + " chars",
            words + " words",
            lines + (lines === 1 ? " line" : " lines"),
        ]
        if (showFullscreenHint) parts.push("Enter to fullscreen")
        return parts.join(_sep)
    }

    // Builds the stats footer for an image entry.
    // width/height are the image's implicitWidth/implicitHeight (0 if not loaded).
    // fileSize is in bytes (0 if not loaded). formatBytesFn is FormatBytes.formatBytes.
    // showFullscreenHint mirrors (root.view === "detail").
    function buildImageStats(width, height, fileSize, formatBytesFn, showFullscreenHint) {
        const parts = []
        if (width > 0) parts.push(width + " \u00d7 " + height + " px")
        if (fileSize > 0) parts.push(formatBytesFn(fileSize))
        if (showFullscreenHint) parts.push("Enter to fullscreen")
        return parts.join(_sep)
    }
}
