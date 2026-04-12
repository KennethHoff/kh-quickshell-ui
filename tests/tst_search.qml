import QtQuick
import QtTest
import "../lib"

TestCase {
    name: "ParseSearch"

    SearchParser { id: parser }

    function test_empty() {
        const r = parser.parseSearch("")
        compare(r.type, "all")
        compare(r.needle, "")
        compare(r.exact, false)
    }

    function test_whitespace_only() {
        const r = parser.parseSearch("   ")
        compare(r.type, "all")
        compare(r.needle, "")
    }

    function test_plain_search() {
        const r = parser.parseSearch("hello")
        compare(r.type, "all")
        compare(r.needle, "hello")
        compare(r.exact, false)
    }

    function test_img_prefix() {
        const r = parser.parseSearch("img:cat")
        compare(r.type, "image")
        compare(r.needle, "cat")
    }

    function test_image_prefix() {
        const r = parser.parseSearch("image:dog")
        compare(r.type, "image")
        compare(r.needle, "dog")
    }

    function test_text_prefix() {
        const r = parser.parseSearch("text:foo bar")
        compare(r.type, "text")
        compare(r.needle, "foobar")
    }

    function test_type_only_no_needle() {
        const r = parser.parseSearch("img:")
        compare(r.type, "image")
        compare(r.needle, "")
    }

    function test_exact_flag() {
        const r = parser.parseSearch("'hello world")
        compare(r.exact, true)
        compare(r.needle, "helloworld")
    }

    function test_exact_with_type() {
        const r = parser.parseSearch("text:'foo bar")
        compare(r.type, "text")
        compare(r.exact, true)
        compare(r.needle, "foobar")
    }

    function test_whitespace_stripped_from_needle() {
        const r = parser.parseSearch("hello world")
        compare(r.needle, "helloworld")
    }

    function test_case_insensitive() {
        const r = parser.parseSearch("IMG:Cats")
        compare(r.type, "image")
        compare(r.needle, "cats")
    }
}
