// Bar plugin (data source): RAM used / total from /proc/meminfo.
// Exposes totalKb / availableKb / usedKb / percent. No visuals — compose with
// a sibling Text to render.
import QtQuick
import Quickshell.Io

BarPlugin {
    id: root
    ipcName: "ram"

    property int    interval: 2000
    property string path:     "/proc/meminfo"

    readonly property alias totalKb:     state.totalKb
    readonly property alias availableKb: state.availableKb
    readonly property alias usedKb:      state.usedKb
    readonly property alias percent:     state.percent

    QtObject {
        id: state
        property int totalKb:     0
        property int availableKb: 0
        readonly property int usedKb:  Math.max(0, totalKb - availableKb)
        readonly property int percent: totalKb > 0 ? Math.round((usedKb / totalKb) * 100) : 0
    }

    QtObject {
        id: functionality
        // ui only
        function tick(): void {
            _fv.reload()
            const lines = _fv.text().split("\n")
            for (let i = 0; i < lines.length; i++) {
                const l = lines[i]
                if (l.startsWith("MemTotal:"))          state.totalKb     = functionality.parseKb(l)
                else if (l.startsWith("MemAvailable:")) state.availableKb = functionality.parseKb(l)
            }
        }
        // ui only
        function parseKb(line: string): int {
            const m = line.match(/(\d+)/)
            return m ? parseInt(m[1], 10) : 0
        }
        // ipc only
        function getUsedMb(): int  { return Math.round(state.usedKb  / 1024) }
        // ipc only
        function getTotalMb(): int { return Math.round(state.totalKb / 1024) }
        // ipc only
        function getPercent(): int { return state.percent }
    }

    IpcHandler {
        target: ipcPrefix
        function getUsedMb(): int  { return functionality.getUsedMb() }
        function getTotalMb(): int { return functionality.getTotalMb() }
        function getPercent(): int { return functionality.getPercent() }
    }

    FileView {
        id: _fv
        path: root.path
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
