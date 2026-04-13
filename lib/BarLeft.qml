// Left slot for the bar layout.
// Place this inside the generated BarLayout Item alongside BarRight.
// Children are laid out left-to-right; barHeight and barWindow propagate
// to all BarWidget subtypes via parent?.barHeight / parent?.barWindow.
import QtQuick

Row {
    anchors.left:           parent.left
    anchors.leftMargin:     8
    anchors.verticalCenter: parent.verticalCenter
    spacing: 4

    // Propagate sizing context to child plugins.
    property int barHeight: parent?.barHeight ?? 32
    property var barWindow: parent?.barWindow ?? null
}
