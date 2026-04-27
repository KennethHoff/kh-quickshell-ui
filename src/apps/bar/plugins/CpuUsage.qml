// Bar plugin (data source): aggregate CPU utilisation %.
// Samples /proc/stat and exposes `usage` for consumers (e.g. Text) to bind.
// No visuals of its own — compose with a sibling Text to render.
import QtQuick
import Quickshell.Io

BarPlugin {
    id: root
    ipcName: "cpu"

    property int interval: 2000

    readonly property alias usage: state.usage

    QtObject {
        id: state
        property int usage:     0
        property int prevIdle:  0
        property int prevTotal: 0
    }

    QtObject {
        id: functionality
        // ui only — sample once and compute the rolling delta.
        function tick(): void {
            _fv.reload()
            const line  = _fv.text().split("\n")[0]
            const parts = line.split(/\s+/).slice(1).map(s => parseInt(s, 10) || 0)
            if (parts.length < 5) return
            const idle  = parts[3] + parts[4]
            let total = 0
            for (let i = 0; i < parts.length; i++) total += parts[i]
            if (state.prevTotal > 0) {
                const dt = total - state.prevTotal
                const di = idle  - state.prevIdle
                state.usage = dt > 0 ? Math.round(((dt - di) / dt) * 100) : 0
            }
            state.prevIdle  = idle
            state.prevTotal = total
        }
        // ipc only
        function getUsage(): int { return state.usage }
    }

    IpcHandler {
        target: ipcPrefix
        function getUsage(): int { return functionality.getUsage() }
    }

    FileView {
        id: _fv
        path: "/proc/stat"
        blockAllReads: true
    }

    Timer {
        interval: root.interval
        running:  root.contentVisible
        repeat:   true
        triggeredOnStart: true
        onTriggered: functionality.tick()
    }

    implicitWidth:  0
    implicitHeight: 0
    visible:        false
}
