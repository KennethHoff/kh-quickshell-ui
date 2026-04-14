// macOS-style Control Center panel button for the bar.
// A BarDropdown pre-configured with a ●●● label and 300 px panel width.
//
// Place ControlTile subtypes (TailscalePanel, EthernetPanel, …) and
// detail content (TailscalePeers, DropdownHeader, Repeater, …) as
// direct children — they land in the popup panel column.
//
// Example:
//   ControlPanel {
//       Row {
//           spacing: 8
//           EthernetPanel {}
//           TailscalePanel { id: _ts }
//       }
//       TailscalePeers { source: _ts }
//   }
import QtQuick

BarDropdown {
    label:      "●●●"
    panelWidth: 300
    ipcName:    "controlcenter"
}
