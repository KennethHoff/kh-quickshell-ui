// Human-readable byte formatter used in kh-cliphist.
// Mirrors formatBytes() in kh-cliphist.nix.
import QtQuick

QtObject {
    function formatBytes(n) {
        if (n < 1024) return n + " B"
        if (n < 1024 * 1024) return (n / 1024).toFixed(1) + " KB"
        return (n / (1024 * 1024)).toFixed(1) + " MB"
    }
}
