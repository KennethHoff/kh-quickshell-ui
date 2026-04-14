// Bar plugin: macOS-style Control Center.
//
// Composes ControlPanel, EthernetPanel, TailscalePanel, and TailscalePeers.
// To customise: copy this file, add/remove tile or detail children.
// All state, polling, and theming live inside the respective panel components.
import QtQuick

BarPlugin {
    implicitWidth: _panel.implicitWidth

    ControlPanel {
        id: _panel
        anchors.fill: parent

        Row {
            spacing: 8
            EthernetPanel {}
            TailscalePanel { id: _ts }
        }

        TailscalePeers { source: _ts }
    }
}
