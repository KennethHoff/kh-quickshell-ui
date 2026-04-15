// Tailscale status tile for use inside a BarGroup panel.
// Extends BarPlugin so it participates in the ipcPrefix chain and is
// individually addressable via IPC regardless of nesting depth.
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

BarPlugin {
    id: root
    NixBins { id: bin }

    // ── Sizing — use the tile's natural dimensions, not barHeight ──────────
    implicitWidth:  _tile.implicitWidth
    implicitHeight: _tile.implicitHeight

    // ── State ──────────────────────────────────────────────────────────────
    QtObject {
        id: _state
        property bool   connected: false
        property bool   pending:   false
        property string selfIp:    ""
        property var    peers:     []
    }

    readonly property alias connected: _state.connected
    readonly property alias pending:   _state.pending
    readonly property alias selfIp:    _state.selfIp
    readonly property alias peers:     _state.peers

    // ── IPC ────────────────────────────────────────────────────────────────
    IpcHandler {
        target: ipcPrefix + ".tailscale"
        function isConnected(): bool  { return _state.connected }
        function getSelfIp(): string  { return _state.selfIp }
        function toggle(): void      { functionality.toggle() }
    }

    // ── Tile visuals ───────────────────────────────────────────────────────
    NixConfig { id: _cfg }

    ControlTile {
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
        // ui only
        function onStreamFinished(text: string): void {
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
        // ui only
        function onToggleExited(): void {
            _state.pending = false
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

    Timer {
        id: _timer
        interval: 2000
        running: root.contentVisible
        repeat: true
        onTriggered: functionality.pollIfIdle()
    }
}
