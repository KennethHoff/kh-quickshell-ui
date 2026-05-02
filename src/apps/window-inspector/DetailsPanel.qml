// Details panel — secondary surface attached to the picked window.
//
// Hosts copy / dispatch keybinds in a scope where they can be mnemonic
// without colliding with the global keymap (the inspector's top level
// stays at f / Esc / q / Enter). Anchored at the centre of the focused
// monitor and sized statically; the parent gates visibility on
// `detailsShowing`.
//
// Auto-freezes when opened upstream, so the cursor can move freely
// while the user reads / acts here.
import QtQuick

Item {
    id: root

    // ── Inputs ────────────────────────────────────────────────────────────────
    property var ipc: null

    // ── Style ─────────────────────────────────────────────────────────────────
    property color  bgColor:     "#181825"
    property color  headerBg:    "#313244"
    property color  textColor:   "#cdd6f4"
    property color  mutedColor:  "#6c7086"
    property color  keyColor:    "#89b4fa"
    property color  warnColor:   "#f9e2af"
    property color  stableColor: "#a6e3a1"
    property string fontFamily:  "monospace"
    property int    fontSize:    14

    // ── Pre-computed strings — same shape as InspectorTag ─────────────────────
    readonly property string _initialClass: (ipc && ipc.initialClass) || ""
    readonly property string _liveClass:    (ipc && ipc.class)        || ""
    readonly property string _initialTitle: (ipc && ipc.initialTitle) || ""
    readonly property string _liveTitle:    (ipc && ipc.title)        || ""
    readonly property string _address:      (ipc && ipc.address)      || ""
    readonly property string _pid:          ipc && ipc.pid !== undefined ? String(ipc.pid) : ""
    readonly property string _wsName:       ipc && ipc.workspace ? (ipc.workspace.name || String(ipc.workspace.id)) : ""
    readonly property string _monitor:      ipc && ipc.monitor !== undefined ? String(ipc.monitor) : ""
    readonly property string _flags:        {
        if (!ipc) return ""
        const f = []
        if (ipc.floating) f.push("floating")
        if (ipc.fullscreen) f.push("fullscreen")
        if (ipc.pinned) f.push("pinned")
        return f.length ? f.join(" · ") : "—"
    }
    readonly property string _atGlobal:   ipc && ipc.at   ? ipc.at[0]   + "," + ipc.at[1]   : ""
    readonly property string _sizeGlobal: ipc && ipc.size ? ipc.size[0] + "x" + ipc.size[1] : ""

    function _show(s) { return s !== "" ? s : "—" }

    readonly property int _panelW: 520

    // ── Backdrop — dim everything else on this surface ───────────────────────
    Rectangle {
        anchors.fill: parent
        color: "#aa000000"
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: root._panelW
        height: contentCol.implicitHeight + 24
        color: root.bgColor
        radius: 10
        border.width: 2
        border.color: root.warnColor

        Column {
            id: contentCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 12
            spacing: 10

            // Header
            Row {
                spacing: 12
                Text {
                    text: "DETAILS"
                    color: root.warnColor
                    font.family: root.fontFamily
                    font.pixelSize: root.fontSize - 2
                    font.bold: true
                    font.letterSpacing: 1
                }
                Text {
                    visible: !root.ipc
                    text: "no window picked"
                    color: root.mutedColor
                    font.family: root.fontFamily
                    font.pixelSize: root.fontSize - 3
                }
            }

            // Class column
            Row {
                spacing: 16
                Column {
                    spacing: 1
                    Text {
                        text: "initialClass (rule-stable)"
                        color: root.stableColor
                        font.family: root.fontFamily
                        font.pixelSize: root.fontSize - 4
                    }
                    Text {
                        text: root._show(root._initialClass)
                        color: root.textColor
                        font.family: root.fontFamily
                        font.pixelSize: root.fontSize
                        font.bold: true
                    }
                }
                Column {
                    spacing: 1
                    Text {
                        text: "class (live)"
                        color: root.mutedColor
                        font.family: root.fontFamily
                        font.pixelSize: root.fontSize - 4
                    }
                    Text {
                        text: root._show(root._liveClass)
                        color: root.textColor
                        font.family: root.fontFamily
                        font.pixelSize: root.fontSize
                    }
                }
            }

            // Title column
            Column {
                spacing: 1
                Text {
                    text: "initialTitle (rule-stable)"
                    color: root.stableColor
                    font.family: root.fontFamily
                    font.pixelSize: root.fontSize - 4
                }
                Text {
                    text: root._show(root._initialTitle)
                    color: root.textColor
                    font.family: root.fontFamily
                    font.pixelSize: root.fontSize
                    elide: Text.ElideRight
                    width: root._panelW - 24
                }
                Text {
                    text: "title (live)"
                    color: root.mutedColor
                    font.family: root.fontFamily
                    font.pixelSize: root.fontSize - 4
                    topPadding: 4
                }
                Text {
                    text: root._show(root._liveTitle)
                    color: root.textColor
                    font.family: root.fontFamily
                    font.pixelSize: root.fontSize
                    elide: Text.ElideRight
                    width: root._panelW - 24
                }
            }

            // Identity row
            Row {
                spacing: 18
                Column {
                    spacing: 1
                    Text { text: "pid"; color: root.mutedColor; font.family: root.fontFamily; font.pixelSize: root.fontSize - 4 }
                    Text { text: root._show(root._pid); color: root.textColor; font.family: root.fontFamily; font.pixelSize: root.fontSize - 1 }
                }
                Column {
                    spacing: 1
                    Text { text: "address"; color: root.mutedColor; font.family: root.fontFamily; font.pixelSize: root.fontSize - 4 }
                    Text { text: root._show(root._address); color: root.textColor; font.family: root.fontFamily; font.pixelSize: root.fontSize - 1 }
                }
                Column {
                    spacing: 1
                    Text { text: "workspace"; color: root.mutedColor; font.family: root.fontFamily; font.pixelSize: root.fontSize - 4 }
                    Text { text: root._show(root._wsName); color: root.textColor; font.family: root.fontFamily; font.pixelSize: root.fontSize - 1 }
                }
                Column {
                    spacing: 1
                    Text { text: "monitor"; color: root.mutedColor; font.family: root.fontFamily; font.pixelSize: root.fontSize - 4 }
                    Text { text: root._show(root._monitor); color: root.textColor; font.family: root.fontFamily; font.pixelSize: root.fontSize - 1 }
                }
            }

            // Geometry row
            Row {
                spacing: 18
                Column {
                    spacing: 1
                    Text { text: "at (global)"; color: root.mutedColor; font.family: root.fontFamily; font.pixelSize: root.fontSize - 4 }
                    Text { text: root._show(root._atGlobal); color: root.textColor; font.family: root.fontFamily; font.pixelSize: root.fontSize - 1 }
                }
                Column {
                    spacing: 1
                    Text { text: "size"; color: root.mutedColor; font.family: root.fontFamily; font.pixelSize: root.fontSize - 4 }
                    Text { text: root._show(root._sizeGlobal); color: root.textColor; font.family: root.fontFamily; font.pixelSize: root.fontSize - 1 }
                }
                Column {
                    spacing: 1
                    Text { text: "flags"; color: root.mutedColor; font.family: root.fontFamily; font.pixelSize: root.fontSize - 4 }
                    Text { text: root._show(root._flags); color: root.warnColor; font.family: root.fontFamily; font.pixelSize: root.fontSize - 1 }
                }
            }

            // Divider
            Rectangle {
                width: parent.width
                height: 1
                color: root.headerBg
            }

            // Copy menu
            Column {
                width: parent.width
                spacing: 4

                Text {
                    text: "COPY AS WINDOWRULEV2"
                    color: root.keyColor
                    font.family: root.fontFamily
                    font.pixelSize: root.fontSize - 4
                    font.bold: true
                    font.letterSpacing: 1
                }

                Repeater {
                    model: [
                        { key: "c", desc: "initialClass" },
                        { key: "t", desc: "initialTitle" },
                        { key: "p", desc: "pid" },
                        { key: "a", desc: "address" },
                        { key: "w", desc: "workspace" },
                        { key: "m", desc: "monitor" },
                        { key: "J", desc: "full record (JSON)" }
                    ]
                    delegate: Row {
                        required property var modelData
                        spacing: 12
                        Text {
                            text: modelData.key
                            color: root.keyColor
                            font.family: root.fontFamily
                            font.pixelSize: root.fontSize
                            width: 24
                        }
                        Text {
                            text: modelData.desc
                            color: root.textColor
                            font.family: root.fontFamily
                            font.pixelSize: root.fontSize - 1
                        }
                    }
                }
            }

            // Footer
            Text {
                text: "Esc back · q quit"
                color: root.mutedColor
                font.family: root.fontFamily
                font.pixelSize: root.fontSize - 4
                topPadding: 4
            }
        }
    }
}
