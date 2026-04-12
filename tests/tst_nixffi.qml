// Contract tests for NixConfig.qml and NixBins.qml.
// Verifies that the stubs (and by extension the Nix-generated files) expose
// all expected properties with the right types.
import QtQuick
import QtTest
import NixConfig
import NixBins

Item {
    TestCase {
        name: "NixConfig"

        NixConfig { id: cfg }

        function test_fontFamily_is_nonempty_string() {
            verify(typeof cfg.fontFamily === "string")
            verify(cfg.fontFamily.length > 0)
        }

        function test_fontSize_is_positive_int() {
            verify(typeof cfg.fontSize === "number")
            verify(cfg.fontSize > 0)
        }

        function test_all_colors_exist() {
            const keys = ["base00","base01","base02","base03","base04","base05",
                          "base06","base07","base08","base09","base0A","base0B",
                          "base0C","base0D","base0E","base0F"]
            for (const k of keys) {
                verify(cfg.color[k] !== undefined, k + " missing")
                verify(typeof cfg.color[k] === "string", k + " not a string")
                verify(cfg.color[k].startsWith("#"), k + " not a hex color")
                compare(cfg.color[k].length, 7, k + " wrong length")
            }
        }
    }

    TestCase {
        name: "NixBins"

        NixBins { id: bin }

        function test_all_bins_exist() {
            const keys = ["bash", "cliphist", "hyprctl", "jq", "kitty", "stat", "wlCopy"]
            for (const k of keys) {
                verify(bin[k] !== undefined, k + " missing")
                verify(typeof bin[k] === "string", k + " not a string")
                verify(bin[k].length > 0, k + " is empty")
            }
        }
    }
}
