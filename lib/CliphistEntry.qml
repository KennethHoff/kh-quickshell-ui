// Cliphist entry line parsing for kh-cliphist.
// Each entry line is "<id>\t<preview>". These functions mirror the inline
// expressions for entryPreview() and selectedEntryId in kh-cliphist.nix.
import QtQuick

QtObject {
    // Returns everything after the first tab, or the whole line if no tab.
    function entryPreview(line) {
        const tab = line.indexOf("\t")
        return tab >= 0 ? line.substring(tab + 1) : line
    }

    // Returns everything before the first tab, or the whole line if no tab.
    function entryId(line) {
        const tab = line.indexOf("\t")
        return tab >= 0 ? line.substring(0, tab) : line
    }

    // Returns true if the entry is an image (preview starts with "[[").
    function isImage(line) {
        return entryPreview(line).startsWith("[[")
    }
}
