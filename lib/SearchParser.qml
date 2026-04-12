// Search input parser for kh-cliphist.
// Mirrors parseSearch() in kh-cliphist.nix.
import QtQuick

QtObject {
    // Parses the search field text into a structured query.
    // Supported prefixes: "img:", "image:", "text:"
    // Leading ' switches to exact substring match.
    // Returns { type: "all"|"image"|"text", needle: string, exact: bool }
    function parseSearch(input) {
        const raw = input.toLowerCase().trim()
        if (!raw) return { type: "all", needle: "", exact: false }

        let type = "all"
        let rest = raw
        if (rest.startsWith("img:") || rest.startsWith("image:")) {
            type = "image"
            rest = rest.substring(rest.indexOf(":") + 1).trim()
        } else if (rest.startsWith("text:")) {
            type = "text"
            rest = rest.substring(rest.indexOf(":") + 1).trim()
        }

        const exact = rest.startsWith("'")
        const needle = (exact ? rest.slice(1) : rest).replace(/\s+/g, "")
        return { type, needle, exact }
    }
}
