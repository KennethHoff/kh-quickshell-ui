// Base type for all bar plugins.
//
// Plugins extend this type and set implicitWidth to size themselves.
// implicitHeight tracks barHeight automatically; width/height are bound
// to their implicit counterparts so Row layout works correctly.
//
// cfg is NOT part of this interface — plugins that need theme access
// declare their own `NixConfig { id: cfg }` directly. Since NixConfig.qml
// is placed in $out/ alongside all plugin files, it is auto-discoverable.
//
// Usage (in kh-bar.qml or BarLayout.qml):
//   Clock { barHeight: root.barHeight }
import QtQuick

Item {
    required property int barHeight

    implicitHeight: barHeight

    // Row uses width/height, not implicit* — bind them so plugins size correctly.
    width:  implicitWidth
    height: implicitHeight
}
