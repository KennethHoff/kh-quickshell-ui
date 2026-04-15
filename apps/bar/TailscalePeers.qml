// Tailscale peer list section for use inside ControlPanel.
// Binds to a TailscalePanel instance via the `source` property to show
// this machine's Tailscale IP and all peers with online/offline status.
//
// Hidden when source has no connected peers.
//
// Example:
//   TailscalePanel { id: ts }
//   TailscalePeers { source: ts }
import QtQuick

Column {
    property var source: null

    NixConfig { id: _cfg }

    width:   parent.width
    spacing: 4
    visible: source !== null && source.connected && source.peers.length > 0

    DropdownDivider {
        dividerColor: _cfg.color.base02
        visible:      source !== null && source.connected && source.peers.length > 0
    }

    DropdownHeader {
        text:       source && source.selfIp
                        ? "tailscale: " + source.selfIp
                        : "tailscale not connected"
        textColor:  _cfg.color.base04
        fontFamily: _cfg.fontFamily
        fontSize:   _cfg.fontSize
    }

    Repeater {
        model: source ? source.peers : []
        delegate: DropdownItem {
            dotColor:       modelData.online ? _cfg.color.base0B : _cfg.color.base03
            primaryText:    modelData.hostname
            primaryColor:   modelData.online ? _cfg.color.base05 : _cfg.color.base04
            secondaryText:  modelData.ip
            secondaryColor: _cfg.color.base03
            fontFamily:     _cfg.fontFamily
            fontSize:       _cfg.fontSize
        }
    }
}
