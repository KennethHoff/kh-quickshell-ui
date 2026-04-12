import QtQuick
import QtTest
import "../lib"

TestCase {
    name: "FuzzyScore"

    FuzzyScore { id: fuzzy }

    function test_exact_match() {
        verify(fuzzy.fuzzyScore("hello", "hello") >= 0)
    }

    function test_subsequence_match() {
        verify(fuzzy.fuzzyScore("hlo", "hello") >= 0)
    }

    function test_no_match() {
        compare(fuzzy.fuzzyScore("xyz", "hello"), -1)
    }

    function test_empty_needle() {
        verify(fuzzy.fuzzyScore("", "hello") >= 0)
    }

    function test_empty_haystack() {
        compare(fuzzy.fuzzyScore("a", ""), -1)
    }

    function test_consecutive_scores_higher() {
        verify(fuzzy.fuzzyScore("ab", "abc") > fuzzy.fuzzyScore("ab", "axb"))
    }

    function test_word_boundary_bonus() {
        verify(fuzzy.fuzzyScore("a", "abc") > fuzzy.fuzzyScore("a", "xabc"))
    }

    function test_case_sensitive() {
        compare(fuzzy.fuzzyScore("A", "abc"), -1)
        verify(fuzzy.fuzzyScore("a", "abc") >= 0)
    }
}
