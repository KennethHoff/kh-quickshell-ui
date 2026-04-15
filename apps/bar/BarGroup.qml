// Bar plugin: groups child plugins/panels behind a single dropdown button.
//
// Place any bar plugin or panel component as a direct child — they appear
// inside the dropdown panel column.  Use ipcName to expose toggle/open/close
// via IPC (target "bar.<ipcName>").
//
// Example:
//   BarGroup {
//       label: "●●●"
//       ipcName: "mygroup"
//       panelWidth: 300
//
//       EthernetPanel {}
//       TailscalePanel { id: _ts }
//       TailscalePeers { source: _ts }
//       Volume {}
//   }
//
//   BarGroup { label: "media"; MediaPlayer {} }
import QtQuick

BarPlugin {
    id: root
    NixConfig { id: cfg }

    property string label:      "●●●"
    property string ipcName:    ""
    property real   panelWidth: 280

    implicitWidth: _dropdown.implicitWidth

    // Route child items into the dropdown panel column.
    default property alias content: _dropdown.content

    BarDropdown {
        id: _dropdown
        anchors.fill: parent
        label:       root.label
        labelColor:  cfg.color.base05
        panelBg:     cfg.color.base01
        panelBorder: cfg.color.base02
        fontFamily:  cfg.fontFamily
        fontSize:    cfg.fontSize
        panelWidth:  root.panelWidth
        ipcName:     root.ipcName
    }
}
