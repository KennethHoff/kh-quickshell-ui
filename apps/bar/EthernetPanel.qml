// Ethernet status tile for use inside a BarGroup panel.
// Extends BarPlugin so it participates in the ipcPrefix chain and is
// individually addressable via IPC regardless of nesting depth.
//
// Polls `nmcli -t -f DEVICE,TYPE,STATE dev` every 10 s.
// Shows the active interface name (e.g. eth0) as the sublabel.
import QtQuick
import Quickshell.Io

BarPlugin {
    id: root
    NixBins   { id: bin }
    NixConfig { id: _cfg }

    // ── Sizing — use the tile's natural dimensions, not barHeight ──────────
    implicitWidth:  _tile.implicitWidth
    implicitHeight: _tile.implicitHeight

    // ── State ──────────────────────────────────────────────────────────────
    QtObject {
        id: _state
        property bool   connected: false
        property string iface:     ""
    }

    readonly property alias connected: _state.connected
    readonly property alias iface:     _state.iface

    // ── IPC ────────────────────────────────────────────────────────────────
    IpcHandler {
        target: ipcPrefix + ".ethernet"
        function isConnected(): bool { return _state.connected }
        function getIface(): string  { return _state.iface }
    }

    // ── Tile visuals ───────────────────────────────────────────────────────
    ControlTile {
        id: _tile
        anchors.fill: parent

        label:              "ethernet"
        sublabel:           _state.connected ? _state.iface : "off"
        active:             _state.connected
        activeColor:        _cfg.color.base0D
        inactiveColor:      _cfg.color.base02
        activeLabelColor:   _cfg.color.base00
        inactiveLabelColor: _cfg.color.base05
        sublabelColor:      _cfg.color.base03
        fontFamily:         _cfg.fontFamily
        fontSize:           _cfg.fontSize
    }

    // ── Logic ──────────────────────────────────────────────────────────────
    QtObject {
        id: functionality

        // ui only
        function onStreamFinished(text: string): void {
            const lines = text.trim().split("\n")
            const active = lines.find(l => {
                const parts = l.split(":")
                return parts[1] === "ethernet" && parts[2] === "connected"
            })
            if (active) {
                _state.connected = true
                _state.iface = active.split(":")[0]
            } else {
                _state.connected = false
                _state.iface = ""
            }
        }
        // ui only
        function pollIfIdle(): void { if (!_proc.running) _proc.running = true }
    }

    Process {
        id: _proc
        running: true
        command: [bin.nmcli, "-t", "-f", "DEVICE,TYPE,STATE", "dev"]
        stdout: StdioCollector {
            onStreamFinished: functionality.onStreamFinished(text)
        }
    }

    Timer {
        id: _timer
        interval: 10000
        running: true
        repeat: true
        onTriggered: functionality.pollIfIdle()
    }
}
