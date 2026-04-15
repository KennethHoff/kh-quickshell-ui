// Tailscale peer list section for use inside ControlPanel.
// Binds to a TailscalePanel instance via the `source` property to show
// this machine's Tailscale IP and all peers with online/offline status.
//
// Clicking a peer row runs `tailscale ping -c 1 <ip>` and shows the
// round-trip latency in the secondary label. The result clears after 5 s.
//
// Hidden when source has no connected peers.
//
// Example:
//   TailscalePanel { id: ts }
//   TailscalePeers { source: ts }
import QtQuick
import Quickshell.Io

Column {
    property var source: null

    NixBins   { id: bin  }
    NixConfig { id: _cfg }

    width:   parent.width
    spacing: 4
    visible: source !== null && source.connected && source.peers.length > 0

    DropdownDivider {
        dividerColor: _cfg.color.base02
        visible:      source !== null && source.connected && source.peers.length > 0
    }

    DropdownHeader {
        text:       source && source.selfIp
                        ? "tailscale: " + source.selfIp
                        : "tailscale not connected"
        textColor:  _cfg.color.base04
        fontFamily: _cfg.fontFamily
        fontSize:   _cfg.fontSize
    }

    Repeater {
        model: source ? source.peers : []
        delegate: Item {
            id: _delegate

            property bool   _pending: false
            property string _result:  ""

            width:          parent ? parent.width : 280
            implicitHeight: _item.implicitHeight

            QtObject {
                id: functionality

                // ui only
                function ping(): void {
                    if (_delegate._pending) return
                    _delegate._result  = ""
                    _delegate._pending = true
                    _clearTimer.stop()
                    _pingProc.running = true
                }

                // ui only
                function onPingFinished(text: string): void {
                    _delegate._pending = false
                    const m = text.match(/(\d+ms)/)
                    _delegate._result = m ? m[1] : "?"
                    _clearTimer.restart()
                }

                // ui only
                function onPingExited(exitCode: int): void {
                    if (_delegate._pending) {
                        _delegate._pending = false
                        _delegate._result  = "err"
                        _clearTimer.restart()
                    }
                }

                // ui only
                function clearPing(): void {
                    _delegate._result = ""
                }
            }

            Process {
                id: _pingProc
                command: [bin.tailscale, "ping", "-c", "1", modelData.ip]
                stdout: StdioCollector {
                    onStreamFinished: functionality.onPingFinished(text)
                }
                onExited: (code, status) => functionality.onPingExited(code)
            }

            Timer {
                id: _clearTimer
                interval: 5000
                onTriggered: functionality.clearPing()
            }

            DropdownItem {
                id: _item
                dotColor:       modelData.online ? _cfg.color.base0B : _cfg.color.base03
                primaryText:    modelData.hostname
                primaryColor:   modelData.online ? _cfg.color.base05 : _cfg.color.base04
                secondaryText:  _delegate._pending ? "ping…"
                                    : (_delegate._result !== "" ? _delegate._result : modelData.ip)
                secondaryColor: _delegate._pending ? _cfg.color.base03
                                    : (_delegate._result !== "" ? _cfg.color.base0E : _cfg.color.base03)
                fontFamily:     _cfg.fontFamily
                fontSize:       _cfg.fontSize
            }

            MouseArea {
                anchors.fill: parent
                onClicked: functionality.ping()
            }
        }
    }
}
