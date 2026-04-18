// Bar plugin: CPU and GPU temperatures from /sys/class/hwmon.
// Matches by the sensor's `name` file (e.g. "zenpower" for Ryzen, "amdgpu" for
// the AMD GPU); reads `temp1_input` in milli-°C. Colour-coded against the
// `warmAt` / `hotAt` thresholds.
//
// Shells out once per tick via bash because /sys/class/hwmon enumeration
// requires a directory listing that FileView can't do on its own.
import QtQuick
import Quickshell.Io

BarPlugin {
    id: root
    NixBins   { id: bin }
    NixConfig { id: cfg }

    property string cpuSensor: "zenpower"
    property string gpuSensor: "amdgpu"
    property int    interval:  5000
    property int    warmAt:    60
    property int    hotAt:     80

    QtObject {
        id: state
        property int cpuC: 0
        property int gpuC: 0
    }

    QtObject {
        id: functionality
        // ui only
        function colorFor(c: int): string {
            if (c >= root.hotAt)  return cfg.color.base08
            if (c >= root.warmAt) return cfg.color.base09
            return cfg.color.base05
        }
        // ui only
        function onStreamFinished(text: string): void {
            let cpu = 0, gpu = 0
            const lines = text.trim().split("\n")
            for (let i = 0; i < lines.length; i++) {
                const parts = lines[i].split(" ")
                if (parts.length < 2) continue
                const name = parts[0]
                const raw  = parseInt(parts[1], 10) || 0
                const c    = Math.round(raw / 1000)
                if      (name === root.cpuSensor) cpu = c
                else if (name === root.gpuSensor) gpu = c
            }
            state.cpuC = cpu
            state.gpuC = gpu
        }
        // ui only
        function pollIfIdle(): void { if (!_proc.running) _proc.running = true }
        // ipc only
        function getCpu(): int { return state.cpuC }
        // ipc only
        function getGpu(): int { return state.gpuC }
    }

    IpcHandler {
        target: ipcPrefix + ".temps"
        function getCpu(): int { return functionality.getCpu() }
        function getGpu(): int { return functionality.getGpu() }
    }

    Process {
        id: _proc
        running: true
        command: [
            bin.bash, "-c",
            'for d in /sys/class/hwmon/hwmon*; do ' +
            '  n="$(cat "$d/name" 2>/dev/null)"; ' +
            '  t="$(cat "$d/temp1_input" 2>/dev/null)"; ' +
            '  [ -n "$t" ] && printf "%s %s\\n" "$n" "$t"; ' +
            'done'
        ]
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

    visible: state.cpuC > 0 || state.gpuC > 0
    implicitWidth: visible ? _row.implicitWidth + 16 : 0

    Row {
        id: _row
        anchors.centerIn: parent
        spacing: 8

        Text {
            visible: state.cpuC > 0
            text:    "cpu " + state.cpuC + "°"
            color:   functionality.colorFor(state.cpuC)
            font.family:    cfg.fontFamily
            font.pixelSize: cfg.fontSize - 1
        }
        Text {
            visible: state.gpuC > 0
            text:    "gpu " + state.gpuC + "°"
            color:   functionality.colorFor(state.gpuC)
            font.family:    cfg.fontFamily
            font.pixelSize: cfg.fontSize - 1
        }
    }
}
