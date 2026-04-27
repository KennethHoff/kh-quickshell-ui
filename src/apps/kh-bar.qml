// Status bar — orchestrator.
//
// Daemon: quickshell -c kh-bar
//@ pragma UseQApplication
//
// Owns: one PanelWindow per configured bar instance, the bar chrome
// (background, border), and the Loader that hosts each instance's generated
// BarLayout_<ipcName>.qml. What plugins appear and where is driven entirely
// by those generated files; this file is identity-free.
import QtQuick
import Quickshell
import Quickshell.Hyprland

ShellRoot {
    id: root

    NixConfig { id: cfg }

    readonly property int barHeight: 32

    BarInstances { id: registry }

    readonly property var liveInstances: {
        const out = []
        const screens = Quickshell.screens
        const configs = registry.instances
        for (let i = 0; i < configs.length; i++) {
            for (let j = 0; j < screens.length; j++) {
                if (screens[j].name === configs[i].screen) {
                    out.push({ ipcName: configs[i].ipcName, screen: screens[j] })
                    break
                }
            }
        }
        return out
    }

    Variants {
        model: root.liveInstances

        delegate: PanelWindow {
            id: barPanel
            required property var modelData

            screen: modelData.screen

            anchors.top:   true
            anchors.left:  true
            anchors.right: true
            implicitHeight: root.barHeight
            exclusiveZone:  root.barHeight

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

                Loader {
                    anchors.fill: parent
                    property int barHeight: root.barHeight
                    property var barWindow: barPanel
                    source: "BarLayout_" + modelData.ipcName + ".qml"
                }
            }
        }
    }
}
