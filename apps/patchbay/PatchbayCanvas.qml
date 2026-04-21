// Top-level graph canvas. Arranges nodes into four primary columns
// (source → virt-source → virt-sink → sink) that follow how audio
// actually routes through PipeWire loopbacks, plus a "Misc" strip on
// the bottom edge for anything outside that flow (MIDI bridges,
// unclassified nodes, etc.).
//
// Links are drawn inside the same content Item as the NodeBoxes so
// `mapToItem` resolves consistently whether a port lives in the main
// grid or in the misc row. Automatic topological layout with
// collision-free routing (roadmap Layout [1]) is a follow-up.
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

    // ── Column definitions ────────────────────────────────────────────────
    readonly property var _mainColumns: [
        { id: "source",      label: "SOURCES"      },
        { id: "virt-source", label: "VIRT SOURCES" },
        { id: "virt-sink",   label: "VIRT SINKS"   },
        { id: "sink",        label: "SINKS"        },
    ]
    readonly property var _mainKinds: ["source", "virt-source", "virt-sink", "sink"]
    readonly property var _miscNodes: nodes.filter(n => !_mainKinds.includes(n.kind))

    function nodesFor(kind: string): var {
        return nodes.filter(n => n.kind === kind)
    }

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

    // ── Content frame — hosts link layer, main grid, and misc row ────────
    Item {
        id: content
        anchors.fill: parent
        anchors.margins: 24
        z: 1

        // Link edges — share this frame so mapToItem coordinates match
        // NodeBoxes in either the main grid or the misc row.
        Repeater {
            id: linkRepeater
            model: root.links
            delegate: LinkEdge {
                anchors.fill: parent
                link: modelData
                nodeItems: root._nodeItems
            }
        }

        // Main 4-column grid — centred horizontally at the top of the canvas
        Item {
            id: mainArea
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            width: root.colWidth * 4 + root.columnGap * 3
            height: labelRow.height + 8 + columnRow.implicitHeight

            Row {
                id: labelRow
                anchors.top: parent.top
                width: parent.width
                spacing: root.columnGap

                Repeater {
                    model: root._mainColumns
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
                            text: root.nodesFor(modelData.id).length
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

                Repeater {
                    model: root._mainColumns
                    delegate: Column {
                        width: root.colWidth
                        spacing: root.rowGap

                        Repeater {
                            model: root.nodesFor(modelData.id)
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

        // Misc strip — anchored to the bottom edge of the canvas so misc
        // nodes sit out of the main flow. Hidden when there are none.
        Item {
            id: miscArea
            visible: root._miscNodes.length > 0
            anchors.left:   parent.left
            anchors.right:  parent.right
            anchors.bottom: parent.bottom
            height: miscDivider.height
                  + miscLabelRow.height
                  + miscFlow.implicitHeight
                  + 20

            Rectangle {
                id: miscDivider
                anchors.left:  parent.left
                anchors.right: parent.right
                anchors.top:   parent.top
                height: 1
                color:  cfg.color.base02
            }

            Row {
                id: miscLabelRow
                anchors.top: miscDivider.bottom
                anchors.left: parent.left
                anchors.topMargin: 8
                spacing: 8

                Text {
                    text: "MISC"
                    color: cfg.color.base03
                    font.family: cfg.fontFamily
                    font.pixelSize: cfg.fontSize - 3
                    font.letterSpacing: 1.5
                }
                Text {
                    text: root._miscNodes.length
                    color: cfg.color.base03
                    font.family: cfg.fontFamily
                    font.pixelSize: cfg.fontSize - 3
                }
            }

            Flow {
                id: miscFlow
                anchors.top:   miscLabelRow.bottom
                anchors.left:  parent.left
                anchors.right: parent.right
                anchors.topMargin: 8
                spacing: root.rowGap

                Repeater {
                    model: root._miscNodes
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
