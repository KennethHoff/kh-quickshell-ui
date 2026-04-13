// Right slot for the bar layout.
// Place this inside the generated BarLayout Item alongside BarLeft.
// Children are laid out right-to-left (layoutDirection: Qt.RightToLeft);
// barHeight and barWindow propagate via parent?.barHeight / parent?.barWindow.
import QtQuick

Row {
    anchors.right:          parent.right
    anchors.rightMargin:    8
    anchors.verticalCenter: parent.verticalCenter
    layoutDirection: Qt.RightToLeft
    spacing: 4

    // Propagate sizing context to child plugins.
    property int barHeight: parent?.barHeight ?? 32
    property var barWindow: parent?.barWindow ?? null
}
