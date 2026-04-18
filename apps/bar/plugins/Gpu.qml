// Bar plugin: AMD GPU utilisation + VRAM use.
// Reads /sys/class/drm/<card>/device/{gpu_busy_percent,mem_info_vram_used,
// mem_info_vram_total}. `cardPath` defaults to card1; override when needed.
//
// Nvidia is not covered here — it needs nvidia-smi (or NVML) shelled out through
// extraBins, and there's no Nvidia hardware on this host to test against. Track
// that work under ROADMAP "System Stats — GPU stats".
import QtQuick
import Quickshell.Io

BarPlugin {
    id: root
    NixConfig { id: cfg }

    property string cardPath:  "/sys/class/drm/card1/device"
    property int    interval:  2000
    property int    hideBelow: 0

    QtObject {
        id: state
        property int  busy:       0
        property real vramUsedB:  0
        property real vramTotalB: 0
        readonly property int vramUsedMb:  Math.round(vramUsedB  / 1024 / 1024)
        readonly property int vramTotalMb: Math.round(vramTotalB / 1024 / 1024)
    }

    QtObject {
        id: functionality
        // ui only
        function tick(): void {
            _fvBusy.reload();  _fvUsed.reload();  _fvTotal.reload()
            state.busy       = parseInt((_fvBusy.text()  || "0").trim(), 10) || 0
            state.vramUsedB  = parseFloat((_fvUsed.text()  || "0").trim()) || 0
            state.vramTotalB = parseFloat((_fvTotal.text() || "0").trim()) || 0
        }
        // ui only
        function fmtGb(bytes: real): string {
            const gb = bytes / 1024 / 1024 / 1024
            return gb >= 10 ? gb.toFixed(0) + "G" : gb.toFixed(1) + "G"
        }
        // ipc only
        function getBusy(): int         { return state.busy }
        // ipc only
        function getVramUsedMb(): int   { return state.vramUsedMb }
        // ipc only
        function getVramTotalMb(): int  { return state.vramTotalMb }
    }

    IpcHandler {
        target: ipcPrefix + ".gpu"
        function getBusy(): int         { return functionality.getBusy() }
        function getVramUsedMb(): int   { return functionality.getVramUsedMb() }
        function getVramTotalMb(): int  { return functionality.getVramTotalMb() }
    }

    FileView { id: _fvBusy;  path: root.cardPath + "/gpu_busy_percent";    blockAllReads: true }
    FileView { id: _fvUsed;  path: root.cardPath + "/mem_info_vram_used";  blockAllReads: true }
    FileView { id: _fvTotal; path: root.cardPath + "/mem_info_vram_total"; blockAllReads: true }

    Timer {
        interval: root.interval
        running:  root.contentVisible
        repeat:   true
        triggeredOnStart: true
        onTriggered: functionality.tick()
    }

    visible: state.busy >= root.hideBelow
    implicitWidth: visible ? _label.implicitWidth + 16 : 0

    Text {
        id: _label
        anchors.centerIn: parent
        color:          cfg.color.base05
        font.family:    cfg.fontFamily
        font.pixelSize: cfg.fontSize - 1
        text: "gpu: " + state.busy + "% (" + functionality.fmtGb(state.vramUsedB) + ")"
    }
}
