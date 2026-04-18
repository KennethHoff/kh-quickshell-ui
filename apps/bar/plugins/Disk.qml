// Bar plugin: disk usage for one or more configured mount points.
// Shells out to `df -B1 <mount>...` on a slow interval (disk fills change slowly).
// Display is "<mount> <used>/<total>" per mount, comma-joined.
import QtQuick
import Quickshell.Io

BarPlugin {
    id: root
    NixBins   { id: bin }
    NixConfig { id: cfg }

    property var mounts:   ["/"]
    property int interval: 60000

    QtObject {
        id: state
        property var results: []  // [{ mount: string, usedB: real, totalB: real }]
    }

    QtObject {
        id: functionality
        // ui only
        function onStreamFinished(text: string): void {
            const res = []
            const lines = text.trim().split("\n")
            // df prints a header; skip it.
            for (let i = 1; i < lines.length; i++) {
                const parts = lines[i].trim().split(/\s+/)
                if (parts.length < 6) continue
                res.push({
                    mount:  parts[parts.length - 1],
                    totalB: parseFloat(parts[1]) || 0,
                    usedB:  parseFloat(parts[2]) || 0,
                })
            }
            state.results = res
        }
        // ui only
        function fmtGb(bytes: real): string {
            const gb = bytes / 1024 / 1024 / 1024
            return gb >= 10 ? gb.toFixed(0) + "G" : gb.toFixed(1) + "G"
        }
        // ui only
        function labelText(): string {
            const out = []
            for (let i = 0; i < state.results.length; i++) {
                const r = state.results[i]
                out.push(r.mount + " " + fmtGb(r.usedB) + "/" + fmtGb(r.totalB))
            }
            return out.join(", ")
        }
        // ui only
        function pollIfIdle(): void { if (!_proc.running) _proc.running = true }
        // ipc only
        function list(): string {
            const out = []
            for (let i = 0; i < state.results.length; i++) {
                const r = state.results[i]
                out.push(r.mount + "\t" + r.usedB + "\t" + r.totalB)
            }
            return out.join("\n")
        }
        // ipc only
        function count(): int { return state.results.length }
    }

    IpcHandler {
        target: ipcPrefix + ".disk"
        function list(): string { return functionality.list() }
        function count(): int   { return functionality.count() }
    }

    Process {
        id: _proc
        running: true
        command: [bin.df, "-B1"].concat(root.mounts)
        stdout: StdioCollector {
            onStreamFinished: functionality.onStreamFinished(text)
        }
    }

    Timer {
        interval: root.interval
        running:  root.contentVisible
        repeat:   true
        onTriggered: functionality.pollIfIdle()
    }

    visible: state.results.length > 0
    implicitWidth: visible ? _label.implicitWidth + 16 : 0

    Text {
        id: _label
        anchors.centerIn: parent
        color:          cfg.color.base05
        font.family:    cfg.fontFamily
        font.pixelSize: cfg.fontSize - 1
        text: functionality.labelText()
    }
}
