// Bar plugin: notification bell.
// Visible only when there are unread notifications. Hidden when count is zero.
//
// Consumes swaync's state via `swaync-client --subscribe-waybar`, which streams
// one JSON line per state change. swaync owns org.freedesktop.Notifications on
// the session bus, which decouples the daemon's lifetime from kh-bar's — kh-bar
// restarts no longer drop the bus name out from under apps mid-Notify.
import QtQuick
import Quickshell.Io

BarPlugin {
    ipcName: "notifications"
    NixBins { id: bin }

    QtObject {
        id: state
        property int unreadCount: 0
    }

    QtObject {
        id: functionality

        // ui only
        function onSubscribeLine(line: string): void {
            try {
                const obj = JSON.parse(line)
                if (typeof obj.count === "number") state.unreadCount = obj.count
            } catch (e) { /* swaync may emit non-JSON status text on connect; ignore */ }
        }
        // ui only — swaync restart or transient client failure: re-subscribe shortly.
        function onSubscribeExited(): void { restartTimer.restart() }
        // ui only
        function onRestartTimer(): void { subscribe.running = true }
        // ipc only
        function getCount(): int { return state.unreadCount }
        // ipc only
        function clear(): void { clearProc.running = true }
    }

    Process {
        id: subscribe
        running: true
        command: [bin.swayncClient, "--subscribe-waybar"]
        stdout: SplitParser {
            onRead: line => functionality.onSubscribeLine(line)
        }
        onExited: functionality.onSubscribeExited()
    }

    Process {
        id: clearProc
        command: [bin.swayncClient, "--close-all"]
    }

    Timer {
        id: restartTimer
        interval: 1000
        onTriggered: functionality.onRestartTimer()
    }

    IpcHandler {
        target: ipcPrefix
        function getCount(): int { return functionality.getCount() }
        function clear(): void   { functionality.clear() }
    }

    visible: state.unreadCount > 0
    implicitWidth: visible ? _bell.implicitWidth + 24 : 0

    BarIcon {
        id: _bell
        anchors.centerIn: parent
        glyph: "\uF0F3"
    }
}
