// Help overlay filter logic for kh-launcher and kh-cliphist.
// Mirrors the ShortcutRow visibility expression and helpFilterKeyBlock in ui.nix.
import QtQuick

QtObject {
    // Returns true if the row should be visible given the current filter string.
    // Mirrors ShortcutRow.visible in ui.nix.
    function rowMatches(filter, shortcut, description) {
        const f = filter.toLowerCase()
        if (!f) return true
        return shortcut.toLowerCase().includes(f) || description.toLowerCase().includes(f)
    }

    // Apply a Backspace keypress to the filter string.
    function applyBackspace(s) {
        return s.slice(0, -1)
    }

    // Apply Ctrl+W (delete last word) to the filter string.
    function applyCtrlW(s) {
        return s.replace(/\S+\s*$/, "")
    }
}
