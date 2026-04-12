// Reusable searchable keybind popup, built on Overlay.
//
// The caller supplies binding data via `sections`; this component handles
// rendering, filtering, and keyboard navigation.
//
// Usage:
//   HelpOverlay {
//       id: help
//       anchors.fill: parent      // must cover the panel so backdrop works
//       sections: root.mode === "insert" ? insertSections : normalSections
//       bgColor:    cfg.color.base01
//       headerBg:   cfg.color.base02
//       textColor:  cfg.color.base05
//       keyColor:   cfg.color.base0D
//       dimColor:   cfg.color.base03
//       fontFamily: cfg.fontFamily
//       fontSize:   cfg.fontSize
//   }
//   Keys.onPressed: (e) => { if (help.showing) { help.handleKey(e); e.accepted = true } }
//
// Sections format:
//   [ { title: "NORMAL MODE", bindings: [ { key: "j / k", desc: "navigate" }, ... ] }, ... ]
import QtQuick

Overlay {
    id: overlay

    // ── Extra style ───────────────────────────────────────────────────────────
    property color keyColor: "#89b4fa"

    // ── Content inputs ────────────────────────────────────────────────────────
    property var sections: []   // [{title: string, bindings: [{key, desc}]}]

    // ── Wire footer to filter state ───────────────────────────────────────────
    footerText:      _filtering ? (_filterText || "") : "/  filter  \u00b7  ?  close"
    footerTextColor: (_filtering && _filterText) ? textColor : dimColor

    // ── Public API ─────────────────────────────────────────────────────────────
    function open() {
        showing      = true
        _filterText  = ""
        _filtering   = false
        helpFlick.contentY = 0
    }
    function close() {
        showing     = false
        _filterText = ""
        _filtering  = false
    }

    // Returns true if the event was consumed.
    // Call this from the parent's Keys.onPressed when showing === true.
    function handleKey(event) {
        if (!showing) return false
        if (event.key === Qt.Key_Shift || event.key === Qt.Key_Control ||
            event.key === Qt.Key_Alt   || event.key === Qt.Key_Meta) return false

        const rowH   = 30
        const halfPg = Math.max(rowH, Math.floor(helpFlick.height / 2))

        if (_filtering) {
            if (event.key === Qt.Key_Escape) {
                if (_filterText) { _filterText = ""; _filtering = false }
                else              close()
            } else if (event.key === Qt.Key_Backspace) {
                if (event.modifiers & Qt.ControlModifier)
                    _filterText = _filterText.replace(/\S+\s*$/, "")
                else
                    _filterText = _filterText.slice(0, -1)
                if (!_filterText) _filtering = false
            } else if (event.key === Qt.Key_U && (event.modifiers & Qt.ControlModifier)) {
                _filterText = ""; _filtering = false
            } else if (event.text && event.text.length === 1 &&
                       event.text.charCodeAt(0) >= 32) {
                _filterText += event.text
            }
            return true   // consume everything while filtering
        }

        // Non-filtering mode
        if (event.key === Qt.Key_Escape || event.text === "?") {
            close()
        } else if (event.key === Qt.Key_Slash) {
            _filtering = true; _filterText = ""
        } else if (event.key === Qt.Key_J || event.key === Qt.Key_Down) {
            helpFlick.contentY = Math.min(
                Math.max(0, helpFlick.contentHeight - helpFlick.height),
                helpFlick.contentY + rowH)
        } else if (event.key === Qt.Key_K || event.key === Qt.Key_Up) {
            helpFlick.contentY = Math.max(0, helpFlick.contentY - rowH)
        } else if (event.key === Qt.Key_G && (event.modifiers & Qt.ShiftModifier)) {
            helpFlick.contentY = Math.max(0, helpFlick.contentHeight - helpFlick.height)
        } else if (event.key === Qt.Key_G) {
            helpFlick.contentY = 0
        } else if (event.key === Qt.Key_D && (event.modifiers & Qt.ControlModifier)) {
            helpFlick.contentY = Math.min(
                Math.max(0, helpFlick.contentHeight - helpFlick.height),
                helpFlick.contentY + halfPg)
        } else if (event.key === Qt.Key_U && (event.modifiers & Qt.ControlModifier)) {
            helpFlick.contentY = Math.max(0, helpFlick.contentY - halfPg)
        }
        return true   // consume all keys while showing (prevent bleed-through)
    }

    // ── Private state ─────────────────────────────────────────────────────────
    property string _filterText: ""
    property bool   _filtering:  false

    // ── Content: scrollable binding list ─────────────────────────────────────
    HelpFilter { id: helpFilter }

    Flickable {
        id: helpFlick
        width: parent.width
        height: Math.min(contentCol.implicitHeight, overlay.height * 0.55)
        contentWidth: width
        contentHeight: contentCol.implicitHeight
        clip: true

        Column {
            id: contentCol
            width: helpFlick.width

            Repeater {
                model: overlay.sections
                delegate: Column {
                    id: sectionCol
                    required property var  modelData
                    required property int  index
                    width: contentCol.width

                    property bool _anyVisible: {
                        const bs = modelData.bindings || []
                        return bs.some(function(b) {
                            return helpFilter.rowMatches(overlay._filterText, b.key, b.desc)
                        })
                    }

                    // Section title bar — hidden when all rows are filtered out
                    Rectangle {
                        width: parent.width
                        visible: sectionCol._anyVisible
                        height: visible ? 38 : 0
                        color: overlay.headerBg
                        // Square off bottom corners so content flows flush below
                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            height: 10
                            color: parent.color
                            visible: parent.visible
                        }

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.title
                            color: overlay.keyColor
                            font.family: overlay.fontFamily
                            font.pixelSize: overlay.fontSize - 3
                            font.bold: true
                            font.letterSpacing: 1
                        }
                    }

                    // Binding rows for this section
                    Column {
                        width: parent.width
                        topPadding: 6
                        bottomPadding: 6

                        Repeater {
                            model: sectionCol.modelData.bindings || []
                            delegate: Item {
                                required property var modelData
                                visible: helpFilter.rowMatches(
                                    overlay._filterText, modelData.key, modelData.desc)
                                width: contentCol.width
                                implicitHeight: visible ? 30 : 0
                                height: implicitHeight

                                Text {
                                    x: 16; width: 130
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.key
                                    color: overlay.keyColor
                                    font.family: overlay.fontFamily
                                    font.pixelSize: overlay.fontSize
                                }
                                Text {
                                    x: 154
                                    anchors.right: parent.right
                                    anchors.rightMargin: 16
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.desc
                                    color: overlay.textColor
                                    font.family: overlay.fontFamily
                                    font.pixelSize: overlay.fontSize
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
