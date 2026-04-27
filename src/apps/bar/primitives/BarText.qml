// Pre-styled text primitive for the bar.
// Wraps QtQuick.Text with the theme's font family + size and the default
// foreground colour. Use BarText anywhere you'd reach for a plain Text inside
// the bar structure so plugin output stays visually consistent without
// hand-wiring `cfg.color.*` and `cfg.font*` at every call site.
//
// Override `color` directly to change the foreground (e.g. per-threshold
// colouring). `warnColor` / `errorColor` / `normalColor` expose the theme's
// semantic colours so callers don't need their own NixConfig reference.
//
// Example:
//   BarText { text: "cpu " + cpuUsage.usage + "%" }
//
//   BarText {
//       text: "cpu " + cpuTemp.temp + "°"
//       color: cpuTemp.temp >= 80 ? errorColor
//            : cpuTemp.temp >= 60 ? warnColor
//            :                      normalColor
//   }
import QtQuick

Text {
    id: _root
    NixConfig { id: _cfg }

    readonly property color normalColor: _cfg.color.base05
    readonly property color warnColor:   _cfg.color.base09
    readonly property color errorColor:  _cfg.color.base08
    readonly property color mutedColor:  _cfg.color.base03

    color:          normalColor
    font.family:    _cfg.fontFamily
    font.pixelSize: _cfg.fontSize - 1
}
