// Tailscale status tile for use inside ControlPanel.
// Extends ControlTile — place it in a Row alongside other panel tiles.
//
// Polls `tailscale status --json` every 10 s. Clicking the tile runs
// `tailscale up` or `tailscale down` and re-polls on exit.
//
// Exposes connected, selfIp, and peers so TailscalePeers (or any other
// consumer) can bind to the live state:
//
//   TailscalePanel { id: ts }
//   TailscalePeers { source: ts }
import QtQuick
import Quickshell.Io

ControlTile {
    NixConfig { id: _cfg }

    // ── State ──────────────────────────────────────────────────────────────
    readonly property alias connected: _state.connected
    readonly property alias selfIp:    _state.selfIp
    readonly property alias peers:     _state.peers

    QtObject {
        id: _state
        property bool   connected: false
        property string selfIp:    ""
        property var    peers:     []
    }

    // ── Tile appearance (auto-themed via NixConfig) ────────────────────────
    label:              "tailscale"
    sublabel:           _state.connected ? _state.selfIp : "off"
    active:             _state.connected
    activeColor:        _cfg.color.base0B
    inactiveColor:      _cfg.color.base02
    activeLabelColor:   _cfg.color.base00
    inactiveLabelColor: _cfg.color.base05
    sublabelColor:      _cfg.color.base03
    fontFamily:         _cfg.fontFamily
    fontSize:           _cfg.fontSize

    onTileClicked: {
        _toggle.command = _state.connected
            ? ["tailscale", "down"]
            : ["tailscale", "up"]
        _toggle.running = true
    }

    // ── Processes ──────────────────────────────────────────────────────────
    Process {
        id: _proc
        running: true
        command: ["tailscale", "status", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text)
                    _state.connected = (d.BackendState === "Running")
                    _state.selfIp    = (d.TailscaleIPs ?? [])[0] ?? ""
                    const peerMap    = d.Peer ?? {}
                    _state.peers = Object.values(peerMap)
                        .map(p => ({
                            hostname: p.HostName  ?? "",
                            ip:       (p.TailscaleIPs ?? [])[0] ?? "",
                            online:   p.Online ?? false,
                        }))
                        .sort((a, b) => Number(b.online) - Number(a.online))
                } catch (_) {
                    _state.connected = false
                    _state.peers     = []
                }
            }
        }
    }

    Process {
        id: _toggle
        onExited: { _proc.running = true }
    }

    Timer {
        id: _timer
        interval: 10000
        running: true
        repeat: true
        onTriggered: if (!_proc.running) _proc.running = true
    }
}
