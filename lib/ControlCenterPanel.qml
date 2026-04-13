// Generic macOS-style Control Center panel for kh-bar plugins.
//
// Renders a ●●● (or custom label) bar button that opens a popup panel
// with two distinct zones:
//
//   tiles   — a wrapping Flow of ControlTile items at the top
//   content — (default) arbitrary items stacked below the tiles
//
// Usage inside a plugin body:
//
//   implicitWidth: cc.implicitWidth
//
//   ControlCenterPanel {
//       id: cc
//       anchors.fill: parent
//       panelBg:     cfg.color.base01
//       panelBorder: cfg.color.base02
//       fontFamily:  cfg.fontFamily
//       fontSize:    cfg.fontSize
//
//       // Tile children — go into the tile Flow at the top of the panel.
//       ControlTile { ... }
//       ControlTile { ... }
//
//       // Non-tile children — go below the tiles.
//       DropdownDivider { ... }
//       DropdownHeader  { ... }
//       Repeater        { ... }
//   }
//
// Tiles vs content: ControlTile children are detected by type and routed
// to the tile row automatically; everything else lands in the content
// column below.
//
// barWindow and barHeight are read automatically from the plugin wrapper.
import QtQuick
import Quickshell

Item {
    id: root

    // ── Bar button ─────────────────────────────────────────────────────────
    property string label:      "●●●"
    property color  labelColor: "#cdd6f4"
    property string fontFamily: "monospace"
    property int    fontSize:   13

    // ── Panel styling ──────────────────────────────────────────────────────
    property color panelBg:     "#1e1e2e"
    property color panelBorder: "#313244"
    property real  panelWidth:  300

    // Toggle — set to true to show the panel.
    property bool open: false

    // Tile children go into the tile Flow; everything else into the content column.
    // Both are exposed so callers can mix ControlTile and non-tile items as
    // direct children of ControlCenterPanel.
    property alias tiles:   tileFlow.data
    default property alias content: contentCol.data

    // Read from the plugin wrapper set by bar-layout.nix.
    readonly property var  _barWindow: parent ? parent.barWindow : null
    readonly property int  _barHeight: parent ? parent.barHeight : 32

    implicitWidth: _label.implicitWidth + 16

    // ── Bar button visuals ─────────────────────────────────────────────────
    Text {
        id: _label
        anchors.centerIn: parent
        text:           root.label
        color:          root.labelColor
        font.family:    root.fontFamily
        font.pixelSize: root.fontSize - 1
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.open = !root.open
    }

    // ── Popup panel ────────────────────────────────────────────────────────
    PopupWindow {
        anchor.window: root._barWindow
        anchor.rect.x: root._barWindow
            ? Math.max(0, Math.min(
                Math.round(root.mapToItem(null, root.width / 2, 0).x
                    - implicitWidth / 2),
                root._barWindow.width - implicitWidth))
            : 0
        anchor.rect.y: root._barHeight
        visible:       root.open && root._barWindow !== null
        implicitWidth:  root.panelWidth
        implicitHeight: _panelCol.implicitHeight + 16
        color: "transparent"

        Rectangle {
            anchors.fill: parent
            color:        root.panelBg
            border.color: root.panelBorder
            border.width: 1
            radius: 4
        }

        Column {
            id: _panelCol
            anchors {
                top:    parent.top
                left:   parent.left
                right:  parent.right
                margins: 8
            }
            spacing: 8

            // ── Tile row ───────────────────────────────────────────────────
            Flow {
                id: tileFlow
                width: parent.width
                spacing: 8
            }

            // ── Content below tiles ────────────────────────────────────────
            Column {
                id: contentCol
                width: parent.width
                spacing: 4
            }
        }
    }
}
