// Icon primitive: image from a file path, with letter-tile fallback when the
// path is empty or doesn't resolve to a loadable image.
//
// PluginList.qml binds `iconData` and `labelText` on this Item when it
// instantiates it via Loader. Plugins that match this shape (apps,
// hyprland-windows, …) just set `iconDelegate = "LauncherIconFile.qml"` in
// their registration — no per-plugin QML required.
import QtQuick

Item {
    property string iconData: ""
    property string labelText: ""

    NixConfig { id: cfg }

    // Contract check: iconData must be empty or an absolute path. If this
    // fires, the bug is in the caller (a plugin with `iconDelegate =
    // "LauncherIconFile.qml"` emitted something else, or PluginList leaked
    // stale data from another plugin). Qt would otherwise URL-parse the
    // non-path as a hostname and punycode-encode it, masking the origin.
    onIconDataChanged: {
        if (iconData !== "" && !iconData.startsWith("/")) {
            console.warn(`LauncherIconFile: iconData must be "" or an absolute path, got: "${iconData}"`)
        }
    }

    Image {
        id: img
        anchors.fill: parent
        source: iconData !== "" ? "file://" + iconData : ""
        fillMode: Image.PreserveAspectFit
        sourceSize: Qt.size(width, height)
        smooth: true
        visible: status === Image.Ready
    }

    Rectangle {
        anchors.fill: parent
        visible: img.status !== Image.Ready
        color: cfg.color.base02
        radius: 6
        Text {
            anchors.centerIn: parent
            text: labelText.charAt(0).toUpperCase()
            color: cfg.color.base05
            font.family: cfg.fontFamily
            font.pixelSize: 16
            font.bold: true
        }
    }
}
