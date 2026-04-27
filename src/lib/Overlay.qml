// Reusable overlay shell: dimmed backdrop + centered popup.
//
// Provides: backdrop, optional header, content slot, optional footer.
// Children placed inside Overlay go into the content slot.
//
// Usage:
//   Overlay {
//       anchors.fill: parent
//       showing:   someCondition
//       title:     "MY POPUP"             // "" hides the header
//       titleColor: someColor
//       footerText: "y confirm · Esc cancel"  // "" hides the footer
//       bgColor: ...; headerBg: ...; ...
//
//       // Content — slot between header and footer
//       SomeItem { width: parent.width; height: 52 }
//   }
import QtQuick

Item {
    id: root

    // ── Style ─────────────────────────────────────────────────────────────────
    property color  bgColor:         "#181825"
    property color  headerBg:        "#313244"
    property color  textColor:       "#cdd6f4"
    property color  dimColor:        "#45475a"
    property string fontFamily:      "monospace"
    property int    fontSize:        14

    // ── API ───────────────────────────────────────────────────────────────────
    property bool   showing:         false
    property int    maxWidth:        400
    property string title:           ""
    property color  titleColor:      textColor
    property string footerText:      ""
    property color  footerTextColor: dimColor

    // Children land in the content slot between header and footer.
    default property alias overlayContent: contentSlot.data

    // ── Backdrop ──────────────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        visible: root.showing
        color: "#88000000"
        z: 9
    }

    // ── Popup ─────────────────────────────────────────────────────────────────
    Rectangle {
        id: popup
        visible: root.showing
        z: 10
        width: Math.min(root.width - 80, root.maxWidth)
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        color: root.bgColor
        radius: 10
        height: popupCol.implicitHeight

        Column {
            id: popupCol
            width: parent.width

            // Header — hidden when title is empty
            Rectangle {
                width: parent.width
                height: 38
                visible: root.title !== ""
                color: root.headerBg
                radius: popup.radius
                Rectangle {
                    anchors.left: parent.left; anchors.right: parent.right
                    anchors.bottom: parent.bottom; height: popup.radius
                    color: parent.color
                    visible: parent.visible
                }
                Text {
                    anchors.left: parent.left; anchors.leftMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.title
                    color: root.titleColor
                    font.family: root.fontFamily
                    font.pixelSize: root.fontSize - 3
                    font.bold: true
                    font.letterSpacing: 1
                }
            }

            // Content slot
            Item {
                id: contentSlot
                width: parent.width
                height: childrenRect.height
            }

            // Footer — hidden when footerText is empty
            Rectangle {
                width: parent.width
                height: 36
                visible: root.footerText !== ""
                color: root.headerBg
                radius: popup.radius
                Rectangle {
                    anchors.left: parent.left; anchors.right: parent.right
                    anchors.top: parent.top; height: popup.radius
                    color: parent.color
                    visible: parent.visible
                }
                Text {
                    anchors.left: parent.left; anchors.leftMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.footerText
                    color: root.footerTextColor
                    font.family: root.fontFamily
                    font.pixelSize: root.fontSize - 3
                }
            }
        }
    }
}
