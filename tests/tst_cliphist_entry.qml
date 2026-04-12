import QtQuick
import QtTest
import "../lib"

TestCase {
    name: "CliphistEntry"

    CliphistEntry { id: entry }

    // entryPreview ─────────────────────────────────────────────────────────────

    function test_preview_after_tab() {
        compare(entry.entryPreview("123\thello world"), "hello world")
    }

    function test_preview_no_tab_returns_whole_line() {
        compare(entry.entryPreview("no-tab-here"), "no-tab-here")
    }

    function test_preview_empty_string() {
        compare(entry.entryPreview(""), "")
    }

    function test_preview_tab_at_start() {
        compare(entry.entryPreview("\ttext"), "text")
    }

    function test_preview_only_tab() {
        compare(entry.entryPreview("\t"), "")
    }

    function test_preview_multiple_tabs_splits_on_first() {
        compare(entry.entryPreview("1\ta\tb"), "a\tb")
    }

    // entryId ──────────────────────────────────────────────────────────────────

    function test_id_before_tab() {
        compare(entry.entryId("123\thello world"), "123")
    }

    function test_id_no_tab_returns_whole_line() {
        compare(entry.entryId("no-tab-here"), "no-tab-here")
    }

    function test_id_empty_string() {
        compare(entry.entryId(""), "")
    }

    function test_id_tab_at_start() {
        compare(entry.entryId("\ttext"), "")
    }

    function test_id_multiple_tabs_splits_on_first() {
        compare(entry.entryId("1\ta\tb"), "1")
    }

    // isImage ──────────────────────────────────────────────────────────────────

    function test_is_image_binary_preview() {
        verify(entry.isImage("42\t[[binary data ..."))
    }

    function test_is_image_text_entry() {
        verify(!entry.isImage("42\thello world"))
    }

    function test_is_image_no_tab() {
        verify(!entry.isImage("plaintext"))
    }
}
