// Bezier curve connecting two port dots.
//
// Reads port positions from the `nodeItems` map maintained by the canvas —
// each NodeBox registers itself under its node id on completion and
// unregisters on destruction. A Canvas redraws whenever the anchor items
// move or when either endpoint node is resized, so layout changes animate
// correctly without a full scene pass.
import QtQuick

Canvas {
    id: root

    NixConfig { id: cfg }

    property var link: ({})
    property var nodeItems: ({})

    // Resolve the two NodeBoxes that host the source / target ports.
    readonly property var _srcNode: nodeItems[link.srcNodeId] || null
    readonly property var _dstNode: nodeItems[link.dstNodeId] || null

    // The actual dot items live inside each NodeBox's portAnchors map.
    readonly property var _srcDot: _srcNode ? (_srcNode.portAnchors[link.srcPortId] || null) : null
    readonly property var _dstDot: _dstNode ? (_dstNode.portAnchors[link.dstPortId] || null) : null

    // Track geometry so the Canvas repaints on layout change
    readonly property real _srcX: _srcNode ? _srcNode.x : 0
    readonly property real _srcY: _srcNode ? _srcNode.y : 0
    readonly property real _dstX: _dstNode ? _dstNode.x : 0
    readonly property real _dstY: _dstNode ? _dstNode.y : 0
    readonly property real _srcH: _srcNode ? _srcNode.height : 0
    readonly property real _dstH: _dstNode ? _dstNode.height : 0

    onPaint: {
        const ctx = getContext("2d")
        ctx.reset()
        if (!_srcDot || !_dstDot) return

        // Map each dot's centre into this canvas's coordinate space.
        const sp = _srcDot.mapToItem(root,
            _srcDot.width / 2, _srcDot.height / 2)
        const tp = _dstDot.mapToItem(root,
            _dstDot.width / 2, _dstDot.height / 2)

        // Tension scales with horizontal distance so short hops bend
        // gently and long hops across columns curve more dramatically.
        const dx = Math.max(60, Math.abs(tp.x - sp.x) * 0.55)

        const stroke = colorForMediaType(link.mediaType)

        ctx.lineCap  = "round"
        ctx.lineJoin = "round"

        // Halo — a wider translucent stroke under the main line pulls the
        // cable off the dot grid without washing out surrounding content.
        ctx.beginPath()
        ctx.moveTo(sp.x, sp.y)
        ctx.bezierCurveTo(sp.x + dx, sp.y, tp.x - dx, tp.y, tp.x, tp.y)
        ctx.lineWidth = 6
        ctx.strokeStyle = haloForMediaType(link.mediaType)
        ctx.stroke()

        // Core stroke
        ctx.beginPath()
        ctx.moveTo(sp.x, sp.y)
        ctx.bezierCurveTo(sp.x + dx, sp.y, tp.x - dx, tp.y, tp.x, tp.y)
        ctx.lineWidth = 2.25
        ctx.strokeStyle = stroke
        ctx.stroke()
    }

    function colorForMediaType(t: string): string {
        if (t === "audio") return cfg.color.base0D
        if (t === "video") return cfg.color.base0E
        if (t === "midi")  return cfg.color.base0A
        return cfg.color.base0D
    }

    // Lower-opacity halo variant using the same hue. Qt.rgba takes the
    // Color object form, so round-trip through Qt.darker/lighter would
    // drop the alpha channel; easier to rebuild from the CSS hex.
    function haloForMediaType(t: string): string {
        const base = colorForMediaType(t)
        // Pad the hex string to a 6-digit rgb + 55 alpha (≈33% opacity)
        return Qt.rgba(Qt.color(base).r, Qt.color(base).g, Qt.color(base).b, 0.28)
    }

    // Repaint whenever any tracked coordinate shifts
    onWidthChanged:  requestPaint()
    onHeightChanged: requestPaint()
    on_SrcXChanged:  requestPaint()
    on_SrcYChanged:  requestPaint()
    on_DstXChanged:  requestPaint()
    on_DstYChanged:  requestPaint()
    on_SrcHChanged:  requestPaint()
    on_DstHChanged:  requestPaint()
    on_SrcDotChanged: requestPaint()
    on_DstDotChanged: requestPaint()
}
