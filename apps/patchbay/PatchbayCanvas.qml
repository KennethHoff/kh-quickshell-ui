// Top-level graph canvas. Arranges nodes into three columns by kind
// (source → bridge → sink) and draws bezier edges for every link between
// a pair of ports whose pixel positions are known.
//
// Layout is intentionally cheap — a single left-to-right column bucket per
// node kind, centred horizontally on the canvas, with per-column vertical
// stacking. Automatic topological layout with collision-free routing
// (roadmap Layout [1]) is a follow-up.
import QtQuick

Item {
    id: root

    NixConfig { id: cfg }

    property var nodes: []
    property var links: []

    // Map of nodeId → NodeBox for fast port lookup during link rendering.
    property var _nodeItems: ({})

    readonly property real columnGap: 180
    readonly property real rowGap:    20
    readonly property real colWidth:  360
    readonly property real gridStep:  28

    // ── Column buckets ────────────────────────────────────────────────────────
    readonly property var _sources: nodes.filter(n => n.kind === "source")
    readonly property var _bridges: nodes.filter(n => n.kind === "bridge")
    readonly property var _sinks:   nodes.filter(n => n.kind === "sink")

    // ── Canvas surface — a slightly darker rectangle inset from the panel
    //     so nodes (base00) read as "floating" on a base01 work surface.
    Rectangle {
        id: surface
        anchors.fill: parent
        color:        cfg.color.base01
        radius:       8
        border.color: cfg.color.base02
        border.width: 1
        z: 0
    }

    // ── Dot grid background — gives the canvas a node-editor feel ──────────
    Canvas {
        id: grid
        anchors.fill: parent
        z: 0

        readonly property color dotColor: cfg.color.base02

        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            ctx.fillStyle = dotColor
            for (let y = root.gridStep; y < height; y += root.gridStep) {
                for (let x = root.gridStep; x < width; x += root.gridStep) {
                    ctx.beginPath()
                    ctx.arc(x, y, 1.5, 0, 2 * Math.PI)
                    ctx.fill()
                }
            }
        }

        onWidthChanged:  requestPaint()
        onHeightChanged: requestPaint()
    }

    // Empty-state message
    Text {
        anchors.centerIn: parent
        visible: root.nodes.length === 0
        text: "No PipeWire nodes."
        color: cfg.color.base03
        font.family: cfg.fontFamily
        font.pixelSize: cfg.fontSize
        z: 1
    }

    // ── Graph content — column labels + nodes + link overlay ──────────────
    // All three share a common anchor frame so link coordinates resolve
    // consistently regardless of column height differences.
    Item {
        id: content
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.topMargin:    24
        anchors.bottomMargin: 24
        width: root.colWidth * 3 + root.columnGap * 2
        z: 1

        // Link edges — drawn behind nodes but inside the content frame so
        // mapToItem targets share coordinates with the Row below.
        Repeater {
            id: linkRepeater
            model: root.links
            delegate: LinkEdge {
                anchors.fill: parent
                link: modelData
                nodeItems: root._nodeItems
            }
        }

        // Column labels — set the reading frame above each stack
        Row {
            id: labelRow
            width: parent.width
            spacing: root.columnGap

            Repeater {
                model: [
                    { label: "SOURCES", count: root._sources.length },
                    { label: "BRIDGES", count: root._bridges.length },
                    { label: "SINKS",   count: root._sinks.length   },
                ]
                delegate: Item {
                    width: root.colWidth
                    height: 22

                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.label
                        color: cfg.color.base03
                        font.family: cfg.fontFamily
                        font.pixelSize: cfg.fontSize - 3
                        font.letterSpacing: 1.5
                    }
                    Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.count
                        color: cfg.color.base03
                        font.family: cfg.fontFamily
                        font.pixelSize: cfg.fontSize - 3
                    }
                }
            }
        }

        Row {
            id: columnRow
            anchors.top: labelRow.bottom
            anchors.topMargin: 8
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: root.columnGap

            Column {
                width: root.colWidth
                spacing: root.rowGap

                Repeater {
                    model: root._sources
                    delegate: NodeBox {
                        width: root.colWidth
                        node: modelData
                        Component.onCompleted: root._nodeItems[node.id] = this
                        Component.onDestruction: delete root._nodeItems[node.id]
                    }
                }
            }

            Column {
                width: root.colWidth
                spacing: root.rowGap

                Repeater {
                    model: root._bridges
                    delegate: NodeBox {
                        width: root.colWidth
                        node: modelData
                        Component.onCompleted: root._nodeItems[node.id] = this
                        Component.onDestruction: delete root._nodeItems[node.id]
                    }
                }
            }

            Column {
                width: root.colWidth
                spacing: root.rowGap

                Repeater {
                    model: root._sinks
                    delegate: NodeBox {
                        width: root.colWidth
                        node: modelData
                        Component.onCompleted: root._nodeItems[node.id] = this
                        Component.onDestruction: delete root._nodeItems[node.id]
                    }
                }
            }
        }
    }
}
