// Bar plugin: Tailscale connection status with peer dropdown panel.
// Polls `tailscale status --json` every 10 s. Click to open panel.
import QtQuick
import Quickshell.Io

BarWidget {
    NixConfig { id: cfg }

    QtObject {
        id: state
        property bool   connected: false
        property string selfIp:    ""
        property var    peers:     []
    }

    Process {
        id: proc
        running: true
        command: ["tailscale", "status", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d         = JSON.parse(text)
                    state.connected = (d.BackendState === "Running")
                    state.selfIp    = (d.TailscaleIPs ?? [])[0] ?? ""
                    const peerMap   = d.Peer ?? {}
                    state.peers = Object.values(peerMap)
                        .map(p => ({
                            hostname: p.HostName  ?? "",
                            ip:       (p.TailscaleIPs ?? [])[0] ?? "",
                            online:   p.Online ?? false,
                        }))
                        .sort((a, b) => Number(b.online) - Number(a.online))
                } catch (_) {
                    state.connected = false
                    state.peers     = []
                }
            }
        }
    }

    Timer {
        id: timer
        interval: 10000
        running: true
        repeat: true
        onTriggered: if (!proc.running) proc.running = true
    }

    implicitWidth: dropdown.implicitWidth

    BarDropdown {
        id: dropdown
        anchors.fill: parent

        label: {
            if (!state.connected) return "ts: off"
            const n = state.peers.filter(p => p.online).length
            return n > 0 ? "ts: on (" + n + ")" : "ts: on"
        }
        labelColor:  state.connected ? cfg.color.base0B : cfg.color.base03
        panelBg:     cfg.color.base01
        panelBorder: cfg.color.base02
        fontFamily:  cfg.fontFamily
        fontSize:    cfg.fontSize
        panelWidth:  300

        // ── Header: this machine ───────────────────────────────────────────
        DropdownHeader {
            text:       state.selfIp ? "this machine: " + state.selfIp
                                     : "tailscale not connected"
            textColor:  cfg.color.base04
            fontFamily: cfg.fontFamily
            fontSize:   cfg.fontSize
        }

        // ── Peers ──────────────────────────────────────────────────────────
        DropdownDivider {
            dividerColor: cfg.color.base02
            visible: state.peers.length > 0
        }

        Repeater {
            model: state.peers
            delegate: DropdownItem {
                dotColor:      modelData.online ? cfg.color.base0B : cfg.color.base03
                primaryText:   modelData.hostname
                primaryColor:  modelData.online ? cfg.color.base05 : cfg.color.base04
                secondaryText: modelData.ip
                secondaryColor: cfg.color.base03
                fontFamily:    cfg.fontFamily
                fontSize:      cfg.fontSize
            }
        }
    }
}
