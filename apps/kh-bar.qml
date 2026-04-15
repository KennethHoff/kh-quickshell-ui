// Status bar — orchestrator.
//
// Daemon: quickshell -c kh-bar
//@ pragma UseQApplication
//
// This file owns: the panel window and the bar chrome (background, border).
// Which plugins appear and where is determined entirely by BarLayout.qml,
// which is generated at build time by bar-config.nix.
import QtQuick
import Quickshell
import Quickshell.Hyprland

ShellRoot {
    id: root

    NixConfig { id: cfg }

    readonly property int barHeight: 32

    PanelWindow {
        id: barPanel
        anchors.top:   true
        anchors.left:  true
        anchors.right: true
        implicitHeight: root.barHeight
        exclusiveZone: root.barHeight

        Rectangle {
            anchors.fill: parent
            color: cfg.color.base01

            // Bottom border separator
            Rectangle {
                anchors.left:   parent.left
                anchors.right:  parent.right
                anchors.bottom: parent.bottom
                height: 1
                color: cfg.color.base02
            }

            BarLayout {
                anchors.fill: parent
                barHeight: root.barHeight
                barWindow: barPanel
            }
        }
    }
}
