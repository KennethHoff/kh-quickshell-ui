// Details panel — secondary surface attached to the picked window.
//
// Hosts a vim-style row navigator: `j`/`k` (or arrows) move row by
// row, `h`/`l` jump section by section, `y` yanks the highlighted
// row. Each row carries the value to display *and* the value to
// yank — for matcher-capable fields that's a `windowrulev2` line,
// for raw fields (live class/title, geometry) it's the value itself.
// The orchestrator owns the model + selection index; this component
// is purely presentational.
import QtQuick

Item {
    id: root

    // ── Inputs ────────────────────────────────────────────────────────────────
    property var rows:          []   // [{ section, label, value, yank }]
    property int selectedIndex: 0
    // Bumped externally on every yank — the row at `selectedIndex` flashes.
    // Same pattern as ClipDelegate.flash() in cliphist.
    property int yankTick:      0

    // ── Style ─────────────────────────────────────────────────────────────────
    property color  bgColor:        "#181825"
    property color  headerBg:       "#313244"
    property color  textColor:      "#cdd6f4"
    property color  mutedColor:     "#6c7086"
    property color  keyColor:       "#89b4fa"
    property color  warnColor:      "#f9e2af"
    property color  stableColor:    "#a6e3a1"
    property color  highlightColor: "#45475a"
    property string fontFamily:     "monospace"
    property int    fontSize:       14

    readonly property int _panelW: 560

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
            spacing: 6

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
                    visible: root.rows.length === 0
                    text: "no window picked"
                    color: root.mutedColor
                    font.family: root.fontFamily
                    font.pixelSize: root.fontSize - 3
                }
            }

            // Section + row repeater. Section header is emitted whenever
            // the row's section name differs from the previous row's,
            // so we don't have to maintain a parallel "sections" array.
            Repeater {
                model: root.rows
                delegate: Item {
                    id: rowItem
                    required property var modelData
                    required property int index

                    readonly property bool _isSectionStart:
                        index === 0 || root.rows[index - 1].section !== modelData.section
                    readonly property bool _isSelected: index === root.selectedIndex
                    readonly property int  _headerH: _isSectionStart ? 22 : 0

                    width: contentCol.width
                    height: _headerH + 22

                    Text {
                        visible: rowItem._isSectionStart
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.topMargin: rowItem.index === 0 ? 0 : 8
                        text: rowItem.modelData.section.toUpperCase()
                        color: root.keyColor
                        font.family: root.fontFamily
                        font.pixelSize: root.fontSize - 4
                        font.bold: true
                        font.letterSpacing: 1
                    }

                    // Highlight bg — extends the full panel width so the
                    // selected row reads as a clear cursor in a list.
                    Rectangle {
                        id: rowBg
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: 22
                        color: rowItem._isSelected ? root.highlightColor : "transparent"
                        radius: 3

                        // Subtle left-edge caret on the selected row, for
                        // an extra signal beyond the bg highlight.
                        Rectangle {
                            visible: rowItem._isSelected
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: 3
                            color: root.warnColor
                            radius: 1
                        }

                        Row {
                            anchors.left: parent.left
                            anchors.leftMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 12

                            Text {
                                text: rowItem.modelData.label
                                color: rowItem.modelData.section === "Identity"
                                       && (rowItem.modelData.label === "initialClass"
                                        || rowItem.modelData.label === "initialTitle")
                                       ? root.stableColor : root.mutedColor
                                font.family: root.fontFamily
                                font.pixelSize: root.fontSize - 2
                                width: 130
                            }
                            Text {
                                text: rowItem.modelData.value || "—"
                                color: root.textColor
                                font.family: root.fontFamily
                                font.pixelSize: root.fontSize - 1
                                font.bold: rowItem._isSelected
                                elide: Text.ElideRight
                                width: card.width - 180
                            }
                        }

                        // Yank flash — pulses when this row is the selected
                        // row at the moment of a yank tick. Same shape as
                        // ClipDelegate.flash() in cliphist.
                        Rectangle {
                            id: flashOverlay
                            anchors.fill: parent
                            radius: rowBg.radius
                            color: root.stableColor
                            opacity: 0
                            SequentialAnimation {
                                id: flashAnim
                                NumberAnimation {
                                    target: flashOverlay; property: "opacity"
                                    to: 0.55; duration: 60; easing.type: Easing.OutQuad
                                }
                                NumberAnimation {
                                    target: flashOverlay; property: "opacity"
                                    to: 0; duration: 220; easing.type: Easing.InQuad
                                }
                            }
                        }
                    }

                    Connections {
                        target: root
                        function onYankTickChanged() {
                            if (rowItem._isSelected) flashAnim.restart()
                        }
                    }
                }
            }

            // Divider
            Rectangle {
                width: parent.width
                height: 1
                color: root.headerBg
            }

            // Footer
            Text {
                text: "j/k row · h/l section · y yank · Esc back · q quit"
                color: root.mutedColor
                font.family: root.fontFamily
                font.pixelSize: root.fontSize - 4
                topPadding: 6
            }
        }
    }
}
