import QtQuick
import QtTest
import "../lib"

TestCase {
    name: "FormatBytes"

    FormatBytes { id: fmt }

    function test_bytes() {
        compare(fmt.formatBytes(0), "0 B")
        compare(fmt.formatBytes(1), "1 B")
        compare(fmt.formatBytes(1023), "1023 B")
    }

    function test_kilobytes() {
        compare(fmt.formatBytes(1024), "1.0 KB")
        compare(fmt.formatBytes(1536), "1.5 KB")
        compare(fmt.formatBytes(1024 * 1024 - 1), "1024.0 KB")
    }

    function test_megabytes() {
        compare(fmt.formatBytes(1024 * 1024), "1.0 MB")
        compare(fmt.formatBytes(1024 * 1024 * 2.5), "2.5 MB")
    }
}
