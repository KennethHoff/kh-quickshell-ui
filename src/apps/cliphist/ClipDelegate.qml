// Clipboard history list entry delegate.
// Rendered by ClipList's internal ListView.
//
// All dynamic state is injected via required properties — ClipDelegate is
// purely presentational and has no direct references to ClipList internals.
//
// Public API (called by ClipList directly):
//   flash()          — trigger the yank/copy blink animation
//   startDeleteAnim() — trigger the fade-out before deletion
import QtQuick
import Quickshell.Io
import "./lib"

Item {
    id: root

    required property var    modelData        // raw cliphist line
    required property int    index            // position in the filtered list
    required property bool   isCurrent        // list.currentIndex === index
    required property string mode             // "normal" | "insert" | "visual"
    required property int    visualAnchor     // anchor index for visual selection
    required property int    listCurrentIndex // list.currentIndex (for visual range)
    required property var    tsValues         // tsStore.values (reactive)
    required property var    pinValues        // pinStore.values (reactive)

    NixConfig     { id: cfg }
    NixBins       { id: bin }
    CliphistEntry { id: clipEntry }

    readonly property string preview:  clipEntry.entryPreview(root.modelData)
    readonly property bool   isImage:  preview.startsWith("[[")
    readonly property string entryId:  clipEntry.entryId(root.modelData)
    readonly property string tmpPath:  "/tmp/kh-cliphist-" + entryId

    height: isImage ? 64 : 40

    // ── Public API ─────────────────────────────────────────────────────────────
    function flash():           void { blinkAnim.restart() }
    function startDeleteAnim(): void { fadeOutAnim.start() }

    // ── Functionality ──────────────────────────────────────────────────────────
    QtObject {
        id: functionality
        // ui only
        function init(): void { if (root.isImage) imgDecode.running = true }
        // ui only
        function onImgDecodeExited(): void { imgThumb.source = "file://" + root.tmpPath }
    }

    // ── Relative time helper ───────────────────────────────────────────────────
    function _relTime(tsVal): string {
        const ts = parseInt(tsVal) || 0
        if (!ts) return ""
        const diff = Math.floor(Date.now() / 1000) - ts
        if (diff < 60)     return "just now"
        if (diff < 3600)   return Math.floor(diff / 60) + "m ago"
        if (diff < 86400)  return Math.floor(diff / 3600) + "h ago"
        if (diff < 604800) return Math.floor(diff / 86400) + "d ago"
        return Math.floor(diff / 604800) + "w ago"
    }

    // ── Process ────────────────────────────────────────────────────────────────
    Process {
        id: imgDecode
        command: [
            bin.bash, "-c",
            "[ -f \"$1\" ] || printf '%s\\n' \"$2\" | " + bin.cliphist + " decode > \"$1\"",
            "--", root.tmpPath, root.modelData
        ]
        onExited: functionality.onImgDecodeExited()
    }

    Component.onCompleted: functionality.init()

    // ── Visual ─────────────────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        anchors.margins: 2
        color: {
            if (root.mode === "visual") {
                const lo = Math.min(root.visualAnchor, root.listCurrentIndex)
                const hi = Math.max(root.visualAnchor, root.listCurrentIndex)
                if (root.index >= lo && root.index <= hi)
                    return root.isCurrent ? cfg.color.base03 : cfg.color.base02
                return "transparent"
            }
            return root.isCurrent ? cfg.color.base02 : "transparent"
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
            color: root.entryId in root.pinValues ? cfg.color.base0A : "transparent"
        }

        Image {
            id: imgThumb
            visible: root.isImage
            width: 90
            anchors { top: parent.top; bottom: parent.bottom; left: parent.left; margins: 4 }
            fillMode: Image.PreserveAspectFit
            smooth: true; mipmap: true; asynchronous: true
        }

        Text {
            id: tsLabel
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            text: root._relTime(root.tsValues[root.entryId] || "0")
            color: cfg.color.base03
            font.family: cfg.fontFamily
            font.pixelSize: cfg.fontSize - 4
        }

        Text {
            visible: !root.isImage
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: tsLabel.left
            anchors.leftMargin: 14
            anchors.rightMargin: 4
            text: root.preview
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
            color: cfg.color.base0B
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
    }

    NumberAnimation {
        id: fadeOutAnim
        target: root
        property: "opacity"
        to: 0
        duration: 200
        easing.type: Easing.InQuad
    }
}
