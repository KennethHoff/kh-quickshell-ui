// Thin vertical separator for BarRow.
// Place between plugin groups to visually divide them without consuming
// flexible width (use BarSpacer for that).
//
// Example:
//   BarRow {
//       Workspaces {}
//       BarPipe {}
//       MediaPlayer {}
//       BarSpacer {}
//       Clock {}
//   }
//
// Override `pipeColor` for a stronger or theme-coloured separator, or
// `pipeHeight` to match a non-default bar height.
import QtQuick
import QtQuick.Layouts

Rectangle {
    NixConfig { id: _cfg }

    property color pipeColor:  _cfg.color.base03
    property int   pipeHeight: 18
    property int   margins:    6

    Layout.alignment:   Qt.AlignVCenter
    Layout.leftMargin:  margins
    Layout.rightMargin: margins

    implicitWidth:  1
    implicitHeight: pipeHeight
    color:          pipeColor
}
