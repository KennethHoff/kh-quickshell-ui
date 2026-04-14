// A single row inside a BarDropdown panel.
// Shows an optional coloured dot, a primary label, and an optional secondary label.
import QtQuick

Item {
    property color  dotColor:       "transparent"
    property string primaryText:    ""
    property string secondaryText:  ""
    property color  primaryColor:   "#cdd6f4"
    property color  secondaryColor: "#6c7086"
    property string fontFamily:     "monospace"
    property int    fontSize:       13
    property real   primaryWidth:   160

    implicitHeight: 20
    implicitWidth:  parent ? parent.width : 280

    Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6

        // Dot indicator — invisible when dotColor is transparent.
        Rectangle {
            width: 6; height: 6
            radius: 3
            anchors.verticalCenter: parent.verticalCenter
            color: dotColor
            visible: dotColor !== "transparent"
        }

        Text {
            width:          primaryWidth
            text:           primaryText
            color:          primaryColor
            font.family:    fontFamily
            font.pixelSize: fontSize - 2
            elide:          Text.ElideRight
            anchors.verticalCenter: parent.verticalCenter
        }

        Text {
            text:           secondaryText
            color:          secondaryColor
            font.family:    fontFamily
            font.pixelSize: fontSize - 3
            anchors.verticalCenter: parent.verticalCenter
            visible:        secondaryText !== ""
        }
    }
}
