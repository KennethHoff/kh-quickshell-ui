import QtQuick
import QtTest
import "../lib"

TestCase {
    name: "TextStats"

    TextStats  { id: stats }
    FormatBytes { id: fmt }

    // wordCount ────────────────────────────────────────────────────────────────

    function test_wordcount_empty()           { compare(stats.wordCount(""),           0) }
    function test_wordcount_whitespace_only() { compare(stats.wordCount("   \n\t"),    0) }
    function test_wordcount_single()          { compare(stats.wordCount("hello"),      1) }
    function test_wordcount_multiple()        { compare(stats.wordCount("hello world foo"), 3) }
    function test_wordcount_extra_spaces()    { compare(stats.wordCount("a  \t  b"),   2) }
    function test_wordcount_leading_trailing(){ compare(stats.wordCount("  hi there "),2) }

    // lineCount ────────────────────────────────────────────────────────────────

    function test_linecount_single()          { compare(stats.lineCount("hello"),      1) }
    function test_linecount_two()             { compare(stats.lineCount("a\nb"),       2) }
    function test_linecount_trailing_newline(){ compare(stats.lineCount("hello\n"),    2) }
    function test_linecount_blank_line()      { compare(stats.lineCount("a\n\nb"),     3) }
    function test_linecount_empty()           { compare(stats.lineCount(""),           1) }
    function test_linecount_only_newlines()   { compare(stats.lineCount("\n\n"),       3) }

    // buildTextStats ───────────────────────────────────────────────────────────

    function test_text_stats_basic() {
        compare(stats.buildTextStats("hello world", false),
                "11 chars  ·  2 words  ·  1 line")
    }

    function test_text_stats_multiline() {
        compare(stats.buildTextStats("hi\nthere\nfriend", false),
                "15 chars  ·  3 words  ·  3 lines")
    }

    function test_text_stats_singular_line() {
        verify(stats.buildTextStats("one line", false).includes("1 line"))
        verify(!stats.buildTextStats("one line", false).includes("1 lines"))
    }

    function test_text_stats_plural_lines() {
        verify(stats.buildTextStats("a\nb", false).includes("2 lines"))
    }

    function test_text_stats_with_hint() {
        const s = stats.buildTextStats("hello", true)
        verify(s.endsWith("Enter to fullscreen"), s)
    }

    function test_text_stats_without_hint() {
        verify(!stats.buildTextStats("hello", false).includes("fullscreen"))
    }

    // buildImageStats ──────────────────────────────────────────────────────────

    function test_image_stats_empty() {
        compare(stats.buildImageStats(0, 0, 0, fmt.formatBytes, false), "")
    }

    function test_image_stats_dimensions_only() {
        compare(stats.buildImageStats(800, 600, 0, fmt.formatBytes, false),
                "800 × 600 px")
    }

    function test_image_stats_size_only() {
        compare(stats.buildImageStats(0, 0, 1024, fmt.formatBytes, false),
                "1.0 KB")
    }

    function test_image_stats_dimensions_and_size() {
        compare(stats.buildImageStats(800, 600, 1024, fmt.formatBytes, false),
                "800 × 600 px  ·  1.0 KB")
    }

    function test_image_stats_with_hint() {
        const s = stats.buildImageStats(0, 0, 0, fmt.formatBytes, true)
        compare(s, "Enter to fullscreen")
    }

    function test_image_stats_all() {
        const s = stats.buildImageStats(800, 600, 1024, fmt.formatBytes, true)
        compare(s, "800 × 600 px  ·  1.0 KB  ·  Enter to fullscreen")
    }
}
