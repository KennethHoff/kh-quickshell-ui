// Generic macOS-style menu-bar dropdown for kh-bar plugins.
//
// Usage inside a plugin body:
//
//   implicitWidth: dropdown.implicitWidth
//
//   BarDropdown {
//       id: dropdown
//       anchors.fill: parent
//       label:       "my plugin"
//       labelColor:  cfg.color.base05
//       panelBg:     cfg.color.base01
//       panelBorder: cfg.color.base02
//       fontFamily:  cfg.fontFamily
//       fontSize:    cfg.fontSize
//       panelWidth:  280
//
//       DropdownHeader { text: "section heading" ; ... }
//       DropdownItem   { primaryText: "foo"; secondaryText: "bar"; ... }
//       DropdownDivider {}
//   }
//
// barWindow and barHeight are read automatically from the plugin wrapper.
import QtQuick
import Quickshell

Item {
    id: root

    // ── Bar button ─────────────────────────────────────────────────────────
    property string label:      ""
    property color  labelColor: "#cdd6f4"
    property string fontFamily: "monospace"
    property int    fontSize:   13

    // ── Panel styling ──────────────────────────────────────────────────────
    property color panelBg:     "#1e1e2e"
    property color panelBorder: "#313244"
    property real  panelWidth:  240

    // Toggle — set to true to show the panel.
    property bool open: false

    // Children of BarDropdown are placed into the popup content column.
    default property alias content: col.data

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
        implicitHeight: col.implicitHeight + 16
        color: "transparent"

        Rectangle {
            anchors.fill: parent
            color:        root.panelBg
            border.color: root.panelBorder
            border.width: 1
            radius: 4
        }

        Column {
            id: col
            anchors {
                top:    parent.top
                left:   parent.left
                right:  parent.right
                margins: 8
            }
            spacing: 4
        }
    }
}
