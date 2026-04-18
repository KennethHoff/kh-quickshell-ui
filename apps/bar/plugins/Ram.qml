// Bar plugin: RAM used / total from /proc/meminfo.
// Used = MemTotal - MemAvailable. Default display is absolute (e.g. "4.2G/16G");
// set `format: "percent"` for a "27%" readout instead.
import QtQuick
import Quickshell.Io

BarPlugin {
    id: root
    NixConfig { id: cfg }

    property int    interval: 2000
    property string format:   "absolute"  // "absolute" | "percent"

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
                if (l.startsWith("MemTotal:"))      state.totalKb     = functionality.parseKb(l)
                else if (l.startsWith("MemAvailable:")) state.availableKb = functionality.parseKb(l)
            }
        }
        // ui only
        function parseKb(line: string): int {
            const m = line.match(/(\d+)/)
            return m ? parseInt(m[1], 10) : 0
        }
        // ui only
        function fmtGb(kb: int): string {
            const gb = kb / 1024 / 1024
            return gb >= 10 ? gb.toFixed(0) + "G" : gb.toFixed(1) + "G"
        }
        // ipc only
        function getUsedMb(): int  { return Math.round(state.usedKb  / 1024) }
        // ipc only
        function getTotalMb(): int { return Math.round(state.totalKb / 1024) }
        // ipc only
        function getPercent(): int { return state.percent }
    }

    IpcHandler {
        target: ipcPrefix + ".ram"
        function getUsedMb(): int  { return functionality.getUsedMb() }
        function getTotalMb(): int { return functionality.getTotalMb() }
        function getPercent(): int { return functionality.getPercent() }
    }

    FileView {
        id: _fv
        path: "/proc/meminfo"
        blockAllReads: true
    }

    Timer {
        interval: root.interval
        running:  root.contentVisible
        repeat:   true
        triggeredOnStart: true
        onTriggered: functionality.tick()
    }

    implicitWidth: _label.implicitWidth + 16

    Text {
        id: _label
        anchors.centerIn: parent
        color:          cfg.color.base05
        font.family:    cfg.fontFamily
        font.pixelSize: cfg.fontSize - 1
        text: root.format === "percent"
            ? "ram: " + state.percent + "%"
            : "ram: " + functionality.fmtGb(state.usedKb) + "/" + functionality.fmtGb(state.totalKb)
    }
}
