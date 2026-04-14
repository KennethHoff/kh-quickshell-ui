// Flexible spacer for BarRow — expands to fill available width.
// Place between plugins to create space-between, space-around, etc.
//
// Example (left-aligned left group, right-aligned right group):
//   BarRow {
//     Workspaces {}
//     MediaPlayer {}
//     BarSpacer {}
//     ControlCenter {}
//     Clock {}
//   }
import QtQuick
import QtQuick.Layouts

Item {
    Layout.fillWidth: true
    implicitWidth: 1
}
