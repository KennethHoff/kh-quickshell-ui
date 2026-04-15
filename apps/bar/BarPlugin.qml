// Base type for all bar plugins.
//
// Plugins extend this type and set implicitWidth to size themselves.
// implicitHeight tracks barHeight automatically; width/height are bound
// to their implicit counterparts so Row layout works correctly.
//
// barHeight is read from the parent chain (BarLeft/BarRight expose it,
// which read it from the BarLayout Item). Explicit override is still
// possible by setting barHeight directly on the plugin instance.
//
// cfg is NOT part of this interface — plugins that need theme access
// declare their own `NixConfig { id: cfg }` directly. Since NixConfig.qml
// is placed in $out/ alongside all plugin files, it is auto-discoverable.
import QtQuick

Item {
    property int barHeight: parent ? parent.barHeight : 32
    property var barWindow: parent ? parent.barWindow : null

    // Walk the parent chain to find the nearest ancestor that exposes ipcPrefix.
    // Direct parents may be plain layout items (Row, RowLayout) that don't carry
    // ipcPrefix — the walk skips them and finds the nearest BarPlugin, BarRow, or
    // BarDropdown.col that does. Static tree means non-reactive walk is fine.
    readonly property string ipcPrefix: {
        var p = parent
        while (p) {
            if (typeof p.ipcPrefix === 'string') return p.ipcPrefix
            p = p.parent
        }
        return "bar"
    }

    implicitHeight: barHeight

    // Row uses width/height, not implicit* — bind them so plugins size correctly.
    width:  implicitWidth
    height: implicitHeight
}
