// Bar plugin: macOS-style Control Center aggregating network toggles.
// Currently includes Tailscale and WiFi.
// Click the bar button to open the panel.
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
        property bool   exitNode:  false
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

    // ── WiFi state ─────────────────────────────────────────────────────────
    QtObject {
        id: wifiState
        property bool   connected: false
        property string ssid:      ""
    }

    Process {
        id: wifiProc
        running: true
        command: ["nmcli", "-t", "-f", "ACTIVE,SSID", "dev", "wifi"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n")
                const active = lines.find(l => l.startsWith("yes:"))
                if (active) {
                    wifiState.connected = true
                    wifiState.ssid = active.slice(4)
                } else {
                    wifiState.connected = false
                    wifiState.ssid = ""
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
            if (!tsProc.running)   tsProc.running   = true
            if (!wifiProc.running) wifiProc.running = true
        }
    }

    implicitWidth: dropdown.implicitWidth

    BarDropdown {
        id: dropdown
        anchors.fill: parent

        label: "●●●"
        labelColor: cfg.color.base05
        panelBg:    cfg.color.base01
        panelBorder: cfg.color.base02
        fontFamily:  cfg.fontFamily
        fontSize:    cfg.fontSize
        panelWidth:  300

        // ── Tiles row ──────────────────────────────────────────────────────
        Row {
            width: parent.width
            spacing: 8

            ControlTile {
                label:      "wifi"
                sublabel:   wifiState.connected ? wifiState.ssid : "off"
                active:     wifiState.connected
                activeColor:      cfg.color.base0D
                inactiveColor:    cfg.color.base02
                activeLabelColor: cfg.color.base00
                inactiveLabelColor: cfg.color.base05
                sublabelColor:    cfg.color.base03
                fontFamily: cfg.fontFamily
                fontSize:   cfg.fontSize
            }

            ControlTile {
                label:    "tailscale"
                sublabel: tsState.connected ? tsState.selfIp : "off"
                active:   tsState.connected
                activeColor:      cfg.color.base0B
                inactiveColor:    cfg.color.base02
                activeLabelColor: cfg.color.base00
                inactiveLabelColor: cfg.color.base05
                sublabelColor:    cfg.color.base03
                fontFamily: cfg.fontFamily
                fontSize:   cfg.fontSize
                onTileClicked: {
                    const cmd = tsState.connected ? ["tailscale", "down"] : ["tailscale", "up"]
                    tsToggleProc.command = cmd
                    tsToggleProc.running = true
                }
            }
        }

        // ── Tailscale peers ────────────────────────────────────────────────
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

    // ── Tailscale toggle process ───────────────────────────────────────────
    Process {
        id: tsToggleProc
        onExited: {
            tsProc.running = true
        }
    }
}
