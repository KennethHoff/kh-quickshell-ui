// Bar plugin (data source): GPU temperature from /sys/class/hwmon.
// Matches by the sensor's `name` file (default "amdgpu"; use "nvidia" on
// Nvidia). Reads `temp1_input` in milli-°C. No visuals — compose with
// a sibling Text to render.
//
// Shells out once per tick via bash because /sys/class/hwmon enumeration
// requires a directory listing that FileView can't do on its own.
import QtQuick
import Quickshell.Io

BarPlugin {
    id: root
    NixBins { id: bin }

    property string sensor:   "amdgpu"
    property int    interval: 5000

    readonly property alias temp: state.temp

    QtObject {
        id: state
        property int temp: 0
    }

    QtObject {
        id: functionality
        // ui only
        function onStreamFinished(text: string): void {
            const lines = text.trim().split("\n")
            for (let i = 0; i < lines.length; i++) {
                const parts = lines[i].split(" ")
                if (parts.length < 2) continue
                if (parts[0] === root.sensor) {
                    state.temp = Math.round((parseInt(parts[1], 10) || 0) / 1000)
                    return
                }
            }
            state.temp = 0
        }
        // ui only
        function pollIfIdle(): void { if (!_proc.running) _proc.running = true }
        // ipc only
        function getTemp(): int { return state.temp }
    }

    IpcHandler {
        target: ipcPrefix + ".gpuTemp"
        function getTemp(): int { return functionality.getTemp() }
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

    implicitWidth:  0
    implicitHeight: 0
    visible:        false
}
