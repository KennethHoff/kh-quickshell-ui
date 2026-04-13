// Bar plugin: macOS-style Control Center.
// Add or remove ControlTile children in the `tiles:` block to customise
// the tile row; add DropdownHeader / DropdownItem / Repeater children
// below for per-section details.
import QtQuick
import Quickshell.Io

BarWidget {
    NixConfig { id: cfg }

    // ── Tailscale state ────────────────────────────────────────────────────
    QtObject {
        id: tsState
        property bool   connected: false
        property string selfIp:    ""
        property var    peers:     []
    }

    Process {
        id: tsProc
        running: true
        command: ["tailscale", "status", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d           = JSON.parse(text)
                    tsState.connected = (d.BackendState === "Running")
                    tsState.selfIp    = (d.TailscaleIPs ?? [])[0] ?? ""
                    const peerMap     = d.Peer ?? {}
                    tsState.peers = Object.values(peerMap)
                        .map(p => ({
                            hostname: p.HostName  ?? "",
                            ip:       (p.TailscaleIPs ?? [])[0] ?? "",
                            online:   p.Online ?? false,
                        }))
                        .sort((a, b) => Number(b.online) - Number(a.online))
                } catch (_) {
                    tsState.connected = false
                    tsState.peers     = []
                }
            }
        }
    }

    Process {
        id: tsToggleProc
        onExited: { tsProc.running = true }
    }

    // ── Ethernet state ─────────────────────────────────────────────────────
    QtObject {
        id: ethState
        property bool   connected: false
        property string iface:     ""
    }

    Process {
        id: ethProc
        running: true
        command: ["nmcli", "-t", "-f", "DEVICE,TYPE,STATE", "dev"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n")
                const active = lines.find(l => {
                    const parts = l.split(":")
                    return parts[1] === "ethernet" && parts[2] === "connected"
                })
                if (active) {
                    ethState.connected = true
                    ethState.iface = active.split(":")[0]
                } else {
                    ethState.connected = false
                    ethState.iface = ""
                }
            }
        }
    }

    Timer {
        id: timer
        interval: 10000
        running: true
        repeat: true
        onTriggered: {
            if (!tsProc.running)  tsProc.running  = true
            if (!ethProc.running) ethProc.running = true
        }
    }

    implicitWidth: panel.implicitWidth

    ControlCenterPanel {
        id: panel
        anchors.fill: parent

        panelBg:     cfg.color.base01
        panelBorder: cfg.color.base02
        fontFamily:  cfg.fontFamily
        fontSize:    cfg.fontSize

        // ── Tiles ──────────────────────────────────────────────────────────
        tiles: [
            ControlTile {
                label:              "ethernet"
                sublabel:           ethState.connected ? ethState.iface : "off"
                active:             ethState.connected
                activeColor:        cfg.color.base0D
                inactiveColor:      cfg.color.base02
                activeLabelColor:   cfg.color.base00
                inactiveLabelColor: cfg.color.base05
                sublabelColor:      cfg.color.base03
                fontFamily:         cfg.fontFamily
                fontSize:           cfg.fontSize
            },
            ControlTile {
                label:              "tailscale"
                sublabel:           tsState.connected ? tsState.selfIp : "off"
                active:             tsState.connected
                activeColor:        cfg.color.base0B
                inactiveColor:      cfg.color.base02
                activeLabelColor:   cfg.color.base00
                inactiveLabelColor: cfg.color.base05
                sublabelColor:      cfg.color.base03
                fontFamily:         cfg.fontFamily
                fontSize:           cfg.fontSize
                onTileClicked: {
                    tsToggleProc.command = tsState.connected
                        ? ["tailscale", "down"] : ["tailscale", "up"]
                    tsToggleProc.running = true
                }
            }
        ]

        // ── Tailscale peer list ────────────────────────────────────────────
        DropdownDivider {
            dividerColor: cfg.color.base02
            visible: tsState.peers.length > 0
        }

        DropdownHeader {
            text:       tsState.selfIp ? "tailscale: " + tsState.selfIp
                                       : "tailscale not connected"
            textColor:  cfg.color.base04
            fontFamily: cfg.fontFamily
            fontSize:   cfg.fontSize
        }

        Repeater {
            model: tsState.peers
            delegate: DropdownItem {
                dotColor:       modelData.online ? cfg.color.base0B : cfg.color.base03
                primaryText:    modelData.hostname
                primaryColor:   modelData.online ? cfg.color.base05 : cfg.color.base04
                secondaryText:  modelData.ip
                secondaryColor: cfg.color.base03
                fontFamily:     cfg.fontFamily
                fontSize:       cfg.fontSize
            }
        }
    }
}
