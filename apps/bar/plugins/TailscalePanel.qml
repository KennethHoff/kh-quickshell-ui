// Tailscale status tile for use inside a BarGroup panel.
// Extends BarPlugin so it participates in the ipcPrefix chain and is
// individually addressable via IPC regardless of nesting depth.
//
// Polls `tailscale status --json` every 2 s while the panel is open.
// Clicking the tile runs `tailscale up` or `tailscale down` and re-polls
// on exit.
//
// Exposes connected, selfIp, peers, exitNodeIp, and exitNodePending so
// TailscalePeers (or any other consumer) can bind to the live state:
//
//   TailscalePanel { id: ts }
//   TailscalePeers { source: ts }
import QtQuick
import Quickshell.Io

BarPlugin {
    id: root
    ipcName: "tailscale"
    NixBins { id: bin }

    // ── Sizing — use the tile's natural dimensions, not barHeight ──────────
    implicitWidth:  _tile.implicitWidth
    implicitHeight: _tile.implicitHeight

    // ── State ──────────────────────────────────────────────────────────────
    QtObject {
        id: _state
        property bool   connected:        false
        property bool   pending:          false
        property bool   exitNodePending:  false
        property string selfIp:           ""
        property string exitNodeIp:       ""
        property var    peers:            []
    }

    readonly property alias connected:       _state.connected
    readonly property alias pending:         _state.pending
    readonly property alias exitNodePending: _state.exitNodePending
    readonly property alias selfIp:          _state.selfIp
    readonly property alias exitNodeIp:      _state.exitNodeIp
    readonly property alias peers:           _state.peers

    function setExitNode(ip: string): void { functionality.setExitNode(ip) }

    // ── IPC ────────────────────────────────────────────────────────────────
    IpcHandler {
        target: ipcPrefix
        function isConnected(): bool    { return _state.connected }
        function getSelfIp(): string    { return _state.selfIp }
        function getExitNodeIp(): string { return _state.exitNodeIp }
        function toggle(): void         { functionality.toggle() }
        function setExitNode(ip: string): void { functionality.setExitNode(ip) }
    }

    // ── Tile visuals ───────────────────────────────────────────────────────
    NixConfig { id: _cfg }

    BarControlTile {
        id: _tile
        anchors.fill: parent

        label:              "tailscale"
        sublabel:           _state.pending ? "..." : (_state.connected ? _state.selfIp : "off")
        active:             _state.connected
        pending:            _state.pending
        activeColor:        _cfg.color.base0B
        inactiveColor:      _cfg.color.base02
        activeLabelColor:   _cfg.color.base00
        inactiveLabelColor: _cfg.color.base05
        sublabelColor:      _cfg.color.base03
        fontFamily:         _cfg.fontFamily
        fontSize:           _cfg.fontSize

        onTileClicked: functionality.toggle()
    }

    // ── Logic ──────────────────────────────────────────────────────────────
    QtObject {
        id: functionality

        // ui+ipc
        function toggle(): void {
            if (_state.pending) return
            _toggle.command = _state.connected ? [bin.tailscale, "down"] : [bin.tailscale, "up"]
            _state.pending = true
            _toggle.running = true
        }
        // ui+ipc
        function setExitNode(ip: string): void {
            if (_state.exitNodePending) return
            _exitNode.command = [bin.tailscale, "set", "--exit-node", ip]
            _state.exitNodePending = true
            _exitNode.running = true
        }
        // ui only
        function onStreamFinished(text: string): void {
            try {
                const d        = JSON.parse(text)
                _state.connected = (d.BackendState === "Running")
                _state.selfIp    = (d.TailscaleIPs ?? [])[0] ?? ""
                const peerMap    = d.Peer ?? {}
                let activeExitIp = ""
                _state.peers = Object.values(peerMap)
                    .map(p => {
                        const ip = (p.TailscaleIPs ?? [])[0] ?? ""
                        if (p.ExitNode) activeExitIp = ip
                        return {
                            hostname:       p.HostName       ?? "",
                            ip:             ip,
                            online:         p.Online         ?? false,
                            exitNodeOption: p.ExitNodeOption ?? false,
                        }
                    })
                    .sort((a, b) => Number(b.online) - Number(a.online))
                _state.exitNodeIp = activeExitIp
            } catch (_) {
                _state.connected  = false
                _state.exitNodeIp = ""
                _state.peers      = []
            }
        }
        // ui only
        function onToggleExited(): void {
            _state.pending = false
            _proc.running = true
        }
        // ui only
        function onExitNodeExited(): void {
            _state.exitNodePending = false
            _proc.running = true
        }
        // ui only
        function pollIfIdle(): void { if (!_proc.running) _proc.running = true }
    }

    Process {
        id: _proc
        running: true
        command: [bin.tailscale, "status", "--json"]
        stdout: StdioCollector {
            onStreamFinished: functionality.onStreamFinished(text)
        }
    }

    Process {
        id: _toggle
        onExited: functionality.onToggleExited()
    }

    Process {
        id: _exitNode
        onExited: functionality.onExitNodeExited()
    }

    Timer {
        id: _timer
        interval: 2000
        running: root.contentVisible
        repeat: true
        onTriggered: functionality.pollIfIdle()
    }
}
