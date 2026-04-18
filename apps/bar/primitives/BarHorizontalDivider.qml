// Thin horizontal separator spanning the parent's width.
// Use anywhere content stacks vertically and needs a visual break —
// inside BarDropdown panels, between rows in a BarTooltip, etc.
//
// Override `dividerColor` for a stronger or theme-coloured separator,
// `dividerHeight` to make it thicker.
import QtQuick

Rectangle {
    NixConfig { id: _cfg }

    property color dividerColor:  _cfg.color.base02
    property int   dividerHeight: 1

    width:  parent ? parent.width : 0
    height: dividerHeight
    color:  dividerColor
}
