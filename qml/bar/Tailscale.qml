// Bar plugin: Tailscale connection status with peer dropdown panel.
// Shows ts: on/off. Click toggles a panel listing peers with IPs
// and online/offline indicators. Polls `tailscale status --json` every 10 s.
import QtQuick
import Quickshell
import Quickshell.Io

BarWidget {
    NixConfig { id: cfg }

    QtObject {
        id: state
        property bool   connected: false
        property string selfIp:    ""
        property var    peers:     []
        property bool   panelOpen: false
    }

    Process {
        id: proc
        running: true
        command: ["tailscale", "status", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d         = JSON.parse(text)
                    state.connected = (d.BackendState === "Running")
                    state.selfIp    = (d.TailscaleIPs ?? [])[0] ?? ""
                    const peerMap   = d.Peer ?? {}
                    state.peers = Object.values(peerMap)
                        .map(p => ({
                            hostname: p.HostName  ?? "",
                            ip:       (p.TailscaleIPs ?? [])[0] ?? "",
                            online:   p.Online ?? false,
                        }))
                        .sort((a, b) => Number(b.online) - Number(a.online))
                } catch (_) {
                    state.connected = false
                    state.peers     = []
                }
            }
        }
    }

    Timer {
        id: timer
        interval: 10000
        running: true
        repeat: true
        onTriggered: if (!proc.running) proc.running = true
    }

    implicitWidth: label.implicitWidth + 16

    Text {
        id: label
        anchors.centerIn: parent
        color: state.connected ? cfg.color.base0B : cfg.color.base03
        font.family:    cfg.fontFamily
        font.pixelSize: cfg.fontSize - 1
        text: {
            if (!state.connected) return "ts: off"
            const n = state.peers.filter(p => p.online).length
            return n > 0 ? "ts: on (" + n + ")" : "ts: on"
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: state.panelOpen = !state.panelOpen
    }

    PopupWindow {
        id: panel
        anchor.window: layout.barWindow
        anchor.rect.x: layout.barWindow ? layout.barWindow.width - panel.implicitWidth - 8 : 0
        anchor.rect.y: layout.barHeight
        visible: state.panelOpen
        implicitWidth: 300
        implicitHeight: col.implicitHeight + 16
        color: "transparent"

        Rectangle {
            anchors.fill: parent
            color: cfg.color.base01
            border.color: cfg.color.base02
            border.width: 1
            radius: 4
        }

        Column {
            id: col
            anchors {
                top:    parent.top
                left:   parent.left
                right:  parent.right
                margins: 8
            }
            spacing: 4

            // ── Self machine row ───────────────────────────────────────────
            Text {
                width: parent.width
                color: cfg.color.base04
                font.family:    cfg.fontFamily
                font.pixelSize: cfg.fontSize - 2
                text: state.selfIp
                    ? "this machine: " + state.selfIp
                    : "tailscale not connected"
            }

            Rectangle {
                width: parent.width
                height: 1
                color: cfg.color.base02
                visible: state.peers.length > 0
            }

            // ── Peer rows ──────────────────────────────────────────────────
            Repeater {
                model: state.peers
                delegate: Row {
                    spacing: 6

                    Rectangle {
                        width: 6; height: 6
                        radius: 3
                        anchors.verticalCenter: parent.verticalCenter
                        color: modelData.online ? cfg.color.base0B : cfg.color.base03
                    }
                    Text {
                        width: 160
                        color: modelData.online ? cfg.color.base05 : cfg.color.base04
                        font.family:    cfg.fontFamily
                        font.pixelSize: cfg.fontSize - 2
                        text: modelData.hostname
                        elide: Text.ElideRight
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        color: cfg.color.base03
                        font.family:    cfg.fontFamily
                        font.pixelSize: cfg.fontSize - 3
                        text: modelData.ip
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
        }
    }
}
