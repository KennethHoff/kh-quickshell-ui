// Contract tests for NixFFI.qml.
// Verifies that the stub (and by extension the Nix-generated file) exposes
// all expected properties with the right types.
import QtQuick
import QtTest
import NixFFI

TestCase {
    name: "NixFFI"

    NixFFI { id: ffi }

    // Font ─────────────────────────────────────────────────────────────────────

    function test_fontFamily_is_nonempty_string() {
        verify(typeof ffi.fontFamily === "string")
        verify(ffi.fontFamily.length > 0)
    }

    function test_fontSize_is_positive_int() {
        verify(typeof ffi.fontSize === "number")
        verify(ffi.fontSize > 0)
    }

    // Colors ───────────────────────────────────────────────────────────────────

    function test_all_colors_exist() {
        const keys = ["base00","base01","base02","base03","base04","base05",
                      "base06","base07","base08","base09","base0A","base0B",
                      "base0C","base0D","base0E","base0F"]
        for (const k of keys) {
            verify(ffi.color[k] !== undefined, k + " missing")
            verify(typeof ffi.color[k] === "string", k + " not a string")
            verify(ffi.color[k].startsWith("#"), k + " not a hex color")
            compare(ffi.color[k].length, 7, k + " wrong length")
        }
    }

    // Binaries ─────────────────────────────────────────────────────────────────

    function test_all_bins_exist() {
        const keys = ["bash", "cliphist", "hyprctl", "jq", "kitty", "stat", "wlCopy"]
        for (const k of keys) {
            verify(ffi.bin[k] !== undefined, k + " missing")
            verify(typeof ffi.bin[k] === "string", k + " not a string")
            verify(ffi.bin[k].length > 0, k + " is empty")
        }
    }
}
