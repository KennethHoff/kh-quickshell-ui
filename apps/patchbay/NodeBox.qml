// Individual PipeWire node rendered as a titled card with port rows.
// Input ports hug the left edge, output ports hug the right edge, each
// exposing a dot anchor whose scene coordinates LinkEdge reads when
// drawing edges.
//
// Two-band design (header + body) plus a thin kind-keyed accent stripe
// on the left edge so at a glance you can tell a source from a sink
// without reading the media class.
import QtQuick

Rectangle {
    id: root

    NixConfig { id: cfg }

    property var node: ({})

    // Expose port dots to LinkEdge through portAnchors[portId] → Item
    property var portAnchors: ({})

    readonly property var _inputs:  (node.ports || []).filter(p => p.direction === "input")
    readonly property var _outputs: (node.ports || []).filter(p => p.direction === "output")

    readonly property color _accent: {
        // Flow-through gradient so left-to-right reads as one colour ramp:
        //   source (green) → bridge (blue) → sink (red).
        if (node.kind === "source") return cfg.color.base0B
        if (node.kind === "sink")   return cfg.color.base08
        return cfg.color.base0D
    }

    // Header + stacked port rows + vertical padding.
    implicitHeight: header.height
                  + Math.max(_inputs.length, _outputs.length) * 22
                  + 20

    color:        cfg.color.base00
    radius:       10
    border.color: cfg.color.base03
    border.width: 1

    // ── Accent stripe — kind indicator on the left edge ───────────────────
    Rectangle {
        anchors.left:   parent.left
        anchors.top:    parent.top
        anchors.bottom: parent.bottom
        width:  3
        color:  root._accent
        radius: 2
    }

    // ── Header band ───────────────────────────────────────────────────────
    Rectangle {
        id: header
        anchors.top:   parent.top
        anchors.left:  parent.left
        anchors.right: parent.right
        anchors.leftMargin: 3
        height: 42
        color:  cfg.color.base02
        radius: 10

        // Square off the bottom so it joins the body cleanly
        Rectangle {
            anchors.left:   parent.left
            anchors.right:  parent.right
            anchors.bottom: parent.bottom
            height: 10
            color:  parent.color
        }

        Text {
            id: title
            anchors.left:    parent.left
            anchors.right:   parent.right
            anchors.top:     parent.top
            anchors.leftMargin:  10
            anchors.rightMargin: 10
            anchors.topMargin:   4
            text:            node.description || node.name || ""
            color:           cfg.color.base05
            font.family:     cfg.fontFamily
            font.pixelSize:  cfg.fontSize - 1
            font.bold:       true
            elide:           Text.ElideRight
        }

        Text {
            anchors.left:     parent.left
            anchors.right:    parent.right
            anchors.top:      title.bottom
            anchors.leftMargin:  10
            anchors.rightMargin: 10
            anchors.topMargin:   2
            text:             node.mediaClass || ""
            color:            root._accent
            font.family:      cfg.fontFamily
            font.pixelSize:   cfg.fontSize - 4
            font.letterSpacing: 0.5
            elide:            Text.ElideRight
        }
    }

    // Input ports (left column)
    Column {
        anchors.top:        header.bottom
        anchors.left:       parent.left
        anchors.topMargin:  8
        anchors.leftMargin: 3
        spacing: 4
        width: root.width / 2

        Repeater {
            model: root._inputs
            delegate: Item {
                width:  parent.width
                height: 18

                Rectangle {
                    id: dot
                    width: 10
                    height: 10
                    radius: 5
                    color: cfg.color.base0B
                    border.color: cfg.color.base00
                    border.width: 1
                    anchors.left: parent.left
                    anchors.leftMargin: -5
                    anchors.verticalCenter: parent.verticalCenter
                    Component.onCompleted: root.portAnchors[modelData.id] = dot
                    Component.onDestruction: delete root.portAnchors[modelData.id]
                }

                Text {
                    anchors.left: dot.right
                    anchors.leftMargin: 10
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.name
                    color: cfg.color.base04
                    font.family: cfg.fontFamily
                    font.pixelSize: cfg.fontSize - 3
                    elide: Text.ElideRight
                }
            }
        }
    }

    // Output ports (right column)
    Column {
        anchors.top:         header.bottom
        anchors.right:       parent.right
        anchors.topMargin:   8
        anchors.rightMargin: 0
        spacing: 4
        width: root.width / 2

        Repeater {
            model: root._outputs
            delegate: Item {
                width:  parent.width
                height: 18

                Text {
                    anchors.right: dot.left
                    anchors.rightMargin: 10
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.name
                    color: cfg.color.base04
                    font.family: cfg.fontFamily
                    font.pixelSize: cfg.fontSize - 3
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignRight
                }

                Rectangle {
                    id: dot
                    width: 10
                    height: 10
                    radius: 5
                    color: cfg.color.base0A
                    border.color: cfg.color.base00
                    border.width: 1
                    anchors.right: parent.right
                    anchors.rightMargin: -5
                    anchors.verticalCenter: parent.verticalCenter
                    Component.onCompleted: root.portAnchors[modelData.id] = dot
                    Component.onDestruction: delete root.portAnchors[modelData.id]
                }
            }
        }
    }
}
