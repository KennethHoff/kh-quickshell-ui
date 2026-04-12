import QtQuick
import QtTest
import "../lib"

TestCase {
    name: "HelpFilter"

    HelpFilter { id: hf }

    // rowMatches ───────────────────────────────────────────────────────────────

    function test_empty_filter_always_visible() {
        verify(hf.rowMatches("", "↑ / ↓", "Navigate"))
        verify(hf.rowMatches("", "Enter", "Launch"))
    }

    function test_matches_shortcut() {
        verify(hf.rowMatches("enter", "Enter", "Launch"))
    }

    function test_matches_description() {
        verify(hf.rowMatches("launch", "Enter", "Launch"))
    }

    function test_case_insensitive() {
        verify(hf.rowMatches("NAV", "↑ / ↓", "Navigate"))
        verify(hf.rowMatches("ESC", "Esc", "Close"))
    }

    function test_substring_match() {
        verify(hf.rowMatches("work", "Ctrl+1–9", "Launch to workspace"))
    }

    function test_no_match() {
        verify(!hf.rowMatches("zzz", "Enter", "Launch"))
    }

    function test_matches_partial_shortcut() {
        verify(hf.rowMatches("ctrl", "Ctrl+1–9", "Launch to workspace"))
    }

    // applyBackspace ───────────────────────────────────────────────────────────

    function test_backspace_removes_last_char() {
        compare(hf.applyBackspace("hello"), "hell")
    }

    function test_backspace_single_char() {
        compare(hf.applyBackspace("a"), "")
    }

    function test_backspace_empty_string() {
        compare(hf.applyBackspace(""), "")
    }

    // applyCtrlW ───────────────────────────────────────────────────────────────

    function test_ctrlw_removes_last_word() {
        compare(hf.applyCtrlW("hello world"), "hello ")
    }

    function test_ctrlw_removes_only_word() {
        compare(hf.applyCtrlW("hello"), "")
    }

    function test_ctrlw_trailing_spaces_included() {
        // "word  " — the spaces after the word are consumed too
        compare(hf.applyCtrlW("foo bar  "), "foo ")
    }

    function test_ctrlw_empty_string() {
        compare(hf.applyCtrlW(""), "")
    }
}
