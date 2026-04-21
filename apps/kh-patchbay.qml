// PipeWire graph editor — orchestrator.
//
// Daemon: quickshell -p <config-dir>
// Toggle: quickshell ipc -c kh-patchbay call patchbay toggle
//
// This file owns: window, IPC, focus routing, and the top-level canvas.
// PipeWire state lives in PwGraph; rendering lives in PatchbayCanvas.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: root

    NixConfig { id: cfg }
    NixBins   { id: bin }

    property bool showing: false

    // ── PipeWire graph source ─────────────────────────────────────────────────
    PwGraph {
        id: graph
        active: root.showing
    }

    // ── Functionality ─────────────────────────────────────────────────────────
    QtObject {
        id: functionality

        // ui+ipc
        function toggle(): void           { root.showing = !root.showing }
        // ipc only
        function open(): void             { root.showing = true }
        // ui+ipc
        function close(): void            { root.showing = false }
        // ipc only
        function refresh(): void          { graph.refresh() }
        // ipc only
        function listNodes(): string      { return JSON.stringify(graph.nodes) }
        // ipc only
        function listLinks(): string      { return JSON.stringify(graph.links) }
        // ui only
        function onVisibleChanged(): void { if (root.showing) onShow() }
        // ui only
        function onShow(): void           { graph.refresh(); keyHandler.forceActiveFocus() }
        // ui only
        function handleKeyEvent(event): void {
            if (event.key === Qt.Key_Shift || event.key === Qt.Key_Control ||
                event.key === Qt.Key_Alt   || event.key === Qt.Key_Meta) return
            if (event.key === Qt.Key_Escape || event.text === "q") {
                close()
                event.accepted = true
                return
            }
        }
    }

    // ── IPC ───────────────────────────────────────────────────────────────────
    IpcHandler {
        target: "patchbay"
        readonly property bool showing: root.showing

        function toggle(): void       { functionality.toggle() }
        function open(): void         { functionality.open() }
        function close(): void        { functionality.close() }
        function refresh(): void      { functionality.refresh() }
        function listNodes(): string  { return functionality.listNodes() }
        function listLinks(): string  { return functionality.listLinks() }
    }

    // ── Window ────────────────────────────────────────────────────────────────
    WlrLayershell {
        id: win
        visible: root.showing
        color: "transparent"
        layer: WlrLayer.Overlay
        keyboardFocus: WlrKeyboardFocus.Exclusive
        exclusionMode: ExclusionMode.Ignore
        namespace: "kh-patchbay"
        anchors { top: true; bottom: true; left: true; right: true }

        onVisibleChanged: functionality.onVisibleChanged()

        // Backdrop
        Rectangle {
            anchors.fill: parent
            color: "#99000000"
            MouseArea { anchors.fill: parent; onClicked: functionality.close() }
        }

        // Panel
        Rectangle {
            id: panel
            width:  parent.width  * 0.9
            height: parent.height * 0.9
            anchors.centerIn: parent
            color: cfg.color.base00
            radius: 12
            clip: true

            MouseArea { anchors.fill: parent }

            // Key dispatcher
            Item {
                id: keyHandler
                anchors.fill: parent
                focus: true
                Keys.onPressed: (event) => functionality.handleKeyEvent(event)
            }

            // Header
            Item {
                id: header
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: 40

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Patchbay"
                    color: cfg.color.base05
                    font.family: cfg.fontFamily
                    font.pixelSize: cfg.fontSize + 2
                }
                Text {
                    anchors.right: parent.right
                    anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    text: graph.nodes.length + " nodes  \u00b7  " + graph.links.length + " links"
                    color: cfg.color.base03
                    font.family: cfg.fontFamily
                    font.pixelSize: cfg.fontSize - 2
                }
            }

            // Footer
            Item {
                id: footer
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 28

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    text: "q / Esc close"
                    color: cfg.color.base03
                    font.family: cfg.fontFamily
                    font.pixelSize: cfg.fontSize - 3
                }
            }

            // Canvas
            PatchbayCanvas {
                id: canvas
                anchors.top: header.bottom
                anchors.bottom: footer.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 8

                nodes: graph.nodes
                links: graph.links
            }
        }
    }
}
