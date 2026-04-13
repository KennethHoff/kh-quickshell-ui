// Full-width bar row — replaces BarLeft/BarRight.
// Children are laid out left-to-right. Use BarSpacer to push items apart
// (CSS space-between equivalent). Multiple BarRows can coexist in BarLayout.
//
// barHeight and barWindow propagate to child BarWidget types via the
// inner RowLayout's own properties (it is the direct parent of plugin items).
import QtQuick
import QtQuick.Layouts

Item {
    id: root
    anchors.fill: parent
    property int barHeight: parent ? parent.barHeight : 32
    property var barWindow: parent ? parent.barWindow : null

    default property alias content: _layout.data

    RowLayout {
        id: _layout
        anchors {
            fill:         parent
            leftMargin:   8
            rightMargin:  8
        }
        spacing: 4

        // Expose context to direct children (BarWidget reads parent.barHeight / parent.barWindow).
        property int barHeight: root.barHeight
        property var barWindow: root.barWindow
    }
}
