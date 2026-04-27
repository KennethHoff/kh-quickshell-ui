// Pre-themed nerd-font icon primitive.
// Wraps QtQuick.Text with a FontLoader for the bundled nerd-font (set via
// cfg.iconFontFile) so glyphs render deterministically regardless of the
// user's system-wide font configuration. Use for PUA codepoints from the
// bundled font (Font Awesome, MDI, etc.) — not for plain Unicode glyphs,
// which belong in a BarText.
//
// Exposes `normalColor` / `warnColor` / `errorColor` / `mutedColor` so
// callers can override `color` without pulling in their own NixConfig.
//
// Example:
//   BarIcon { glyph: "\uF0F3" }                        // bell
//   BarIcon { glyph: "\u{F075F}"; color: mutedColor }  // mdi-volume-off, muted
//   BarIcon { glyph: "\u{F057E}"; pixelSize: 20 }      // mdi-volume-high, larger
import QtQuick

Text {
    id: _root
    NixConfig { id: _cfg }

    property string glyph:     ""
    property int    pixelSize: _cfg.fontSize

    readonly property color normalColor: _cfg.color.base05
    readonly property color warnColor:   _cfg.color.base09
    readonly property color errorColor:  _cfg.color.base08
    readonly property color mutedColor:  _cfg.color.base03

    FontLoader {
        id: _iconFont
        source: "file://" + _cfg.iconFontFile
    }

    text:           glyph
    color:          normalColor
    font.family:    _iconFont.name
    font.pixelSize: pixelSize
}
