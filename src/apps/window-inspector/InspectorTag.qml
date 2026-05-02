// Floating info tag shown next to the cursor in pick mode (or pinned in
// frozen mode). The educational payload — initialClass / initialTitle —
// sits in its own labelled column so the rule-stable fields are obvious
// at a glance, distinct from the live `class` / `title` that drift at
// runtime (browser tabs being the obvious case).
//
// Cursor position is given in global coords; the parent subtracts the
// layer surface's screen offset before passing them in.
import QtQuick

Item {
    id: root

    // ── Inputs ────────────────────────────────────────────────────────────────
    property var  ipc:        null
    property int  cursorX:    0       // layer-local
    property int  cursorY:    0       // layer-local
    property int  screenW:    0
    property int  screenH:    0
    property bool frozen:     false

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

    // ── Pre-computed strings ──────────────────────────────────────────────────
    // Use `||` defaults so missing fields render as "—" rather than collapsing
    // the row, which would leave the tag mysteriously blank.
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

    // ── Tag positioning — clamp to screen with a small offset ────────────────
    readonly property int _tagW:  Math.min(440, root.width - 20)
    readonly property int _gap:   18

    Rectangle {
        id: card
        // Place to the cursor's bottom-right by default; flip if we'd run
        // off the right edge or bottom edge.
        x: {
            const right = root.cursorX + root._gap
            if (right + width > root.width - 8) return Math.max(8, root.cursorX - width - root._gap)
            return right
        }
        y: {
            const below = root.cursorY + root._gap
            if (below + height > root.height - 8) return Math.max(8, root.cursorY - height - root._gap)
            return below
        }
        // Fixed width avoids a polish loop where Column.implicitWidth feeds
        // back into Text children that bind their `width` to contentCol.width
        // for eliding. Height is still driven by content.
        width: root._tagW
        height: contentCol.implicitHeight + 16
        color: root.bgColor
        radius: 8
        border.width: 2
        border.color: root.frozen ? root.warnColor : root.keyColor

        Column {
            id: contentCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 8
            spacing: 6

            // ── Mode banner ───────────────────────────────────────────────────
            Row {
                spacing: 8
                Text {
                    text: root.frozen ? "FROZEN" : "PICK"
                    color: root.frozen ? root.warnColor : root.keyColor
                    font.family: root.fontFamily
                    font.pixelSize: root.fontSize - 3
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

            // ── Class column — initial vs live ────────────────────────────────
            Row {
                spacing: 12
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

            // ── Title column — initial vs live ────────────────────────────────
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
                    width: root._tagW - 16
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
                    width: root._tagW - 16
                }
            }

            // ── Identity row ──────────────────────────────────────────────────
            Row {
                spacing: 18
                Column {
                    spacing: 1
                    Text {
                        text: "pid"
                        color: root.mutedColor
                        font.family: root.fontFamily
                        font.pixelSize: root.fontSize - 4
                    }
                    Text {
                        text: root._show(root._pid)
                        color: root.textColor
                        font.family: root.fontFamily
                        font.pixelSize: root.fontSize - 1
                    }
                }
                Column {
                    spacing: 1
                    Text {
                        text: "address"
                        color: root.mutedColor
                        font.family: root.fontFamily
                        font.pixelSize: root.fontSize - 4
                    }
                    Text {
                        text: root._show(root._address)
                        color: root.textColor
                        font.family: root.fontFamily
                        font.pixelSize: root.fontSize - 1
                    }
                }
                Column {
                    spacing: 1
                    Text {
                        text: "workspace"
                        color: root.mutedColor
                        font.family: root.fontFamily
                        font.pixelSize: root.fontSize - 4
                    }
                    Text {
                        text: root._show(root._wsName)
                        color: root.textColor
                        font.family: root.fontFamily
                        font.pixelSize: root.fontSize - 1
                    }
                }
                Column {
                    spacing: 1
                    Text {
                        text: "monitor"
                        color: root.mutedColor
                        font.family: root.fontFamily
                        font.pixelSize: root.fontSize - 4
                    }
                    Text {
                        text: root._show(root._monitor)
                        color: root.textColor
                        font.family: root.fontFamily
                        font.pixelSize: root.fontSize - 1
                    }
                }
            }

            // ── Geometry row ──────────────────────────────────────────────────
            Row {
                spacing: 18
                Column {
                    spacing: 1
                    Text {
                        text: "at (global)"
                        color: root.mutedColor
                        font.family: root.fontFamily
                        font.pixelSize: root.fontSize - 4
                    }
                    Text {
                        text: root._show(root._atGlobal)
                        color: root.textColor
                        font.family: root.fontFamily
                        font.pixelSize: root.fontSize - 1
                    }
                }
                Column {
                    spacing: 1
                    Text {
                        text: "size"
                        color: root.mutedColor
                        font.family: root.fontFamily
                        font.pixelSize: root.fontSize - 4
                    }
                    Text {
                        text: root._show(root._sizeGlobal)
                        color: root.textColor
                        font.family: root.fontFamily
                        font.pixelSize: root.fontSize - 1
                    }
                }
                Column {
                    spacing: 1
                    Text {
                        text: "flags"
                        color: root.mutedColor
                        font.family: root.fontFamily
                        font.pixelSize: root.fontSize - 4
                    }
                    Text {
                        text: root._show(root._flags)
                        color: root.warnColor
                        font.family: root.fontFamily
                        font.pixelSize: root.fontSize - 1
                    }
                }
            }

            // ── Footer hint ───────────────────────────────────────────────────
            Text {
                text: root.frozen ? "f unfreeze · Esc quit"
                                  : "f freeze · Esc quit"
                color: root.mutedColor
                font.family: root.fontFamily
                font.pixelSize: root.fontSize - 4
                topPadding: 4
                width: root._tagW - 16
                wrapMode: Text.WordWrap
            }
        }
    }
}
