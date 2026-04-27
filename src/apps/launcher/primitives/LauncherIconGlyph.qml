// Icon primitive: literal text/glyph centred in the slot, sized to fill ~75%
// of the slot height. Used by plugins whose icon column carries a character
// (emoji picker; future: unicode symbols, single-char shortcut indicators).
//
// PluginList.qml binds `iconData` on this Item when it instantiates it via
// Loader. Plugins set `iconDelegate = "LauncherIconGlyph.qml"` to opt in.
// `labelText` is ignored — text icons don't need a fallback.
import QtQuick

Item {
    property string iconData: ""
    property string labelText: ""

    Text {
        anchors.centerIn: parent
        text: iconData
        font.pixelSize: Math.round(parent.height * 0.75)
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }
}
