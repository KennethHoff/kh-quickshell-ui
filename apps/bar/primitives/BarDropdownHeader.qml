// A muted info/section-header row inside a BarDropdown panel.
import QtQuick

Text {
    property string fontFamily: "monospace"
    property int    fontSize:   13
    property color  textColor:  "#6c7086"

    width: parent ? parent.width : 200
    color:          textColor
    font.family:    fontFamily
    font.pixelSize: fontSize - 2
    elide: Text.ElideRight
}
