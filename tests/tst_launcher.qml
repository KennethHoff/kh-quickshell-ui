import QtQuick
import QtTest
import "../lib"

Item {

// ── FilterApps ────────────────────────────────────────────────────────────────

TestCase {
    name: "FilterApps"

    LauncherFilter { id: filter }

    property var apps: [
        { name: "Firefox",    genericName: "Web Browser",        noDisplay: false },
        { name: "Terminal",   genericName: "Terminal Emulator",  noDisplay: false },
        { name: "Chromium",   genericName: "Web Browser",        noDisplay: false },
        { name: "Hidden App", genericName: "",                   noDisplay: true  },
        { name: "Neovim",     genericName: "Text Editor",        noDisplay: false },
    ]

    function test_empty_query_returns_all_visible() {
        compare(filter.filterApps(apps, "").length, 4)
    }

    function test_nodisplay_always_excluded() {
        const result = filter.filterApps(apps, "")
        for (const e of result)
            verify(!e.noDisplay, e.name + " should be hidden")
    }

    function test_sorted_alphabetically() {
        const names = filter.filterApps(apps, "").map(e => e.name)
        compare(names, ["Chromium", "Firefox", "Neovim", "Terminal"])
    }

    function test_fuzzy_matches_name() {
        const result = filter.filterApps(apps, "fox")
        compare(result.length, 1)
        compare(result[0].name, "Firefox")
    }

    function test_fuzzy_matches_generic_name() {
        const result = filter.filterApps(apps, "editor")
        compare(result.length, 1)
        compare(result[0].name, "Neovim")
    }

    function test_fuzzy_no_match_returns_empty() {
        compare(filter.filterApps(apps, "zzzzz").length, 0)
    }

    function test_space_separated_terms_anded() {
        // "fire" AND "fox" both fuzzy-match Firefox
        const result = filter.filterApps(apps, "fire fox")
        compare(result.length, 1)
        compare(result[0].name, "Firefox")
    }

    function test_space_separated_terms_no_match_if_any_fails() {
        // "fire" matches Firefox, "zzz" matches nothing — AND fails
        compare(filter.filterApps(apps, "fire zzz").length, 0)
    }

    function test_fuzzy_matches_across_word_boundary() {
        // Single token spanning name + genericName boundary via fuzzy
        const result = filter.filterApps(apps, "termemu")
        compare(result.length, 1)
        compare(result[0].name, "Terminal")
    }

    function test_exact_matches_substring() {
        const result = filter.filterApps(apps, "'web")
        const names = result.map(e => e.name).sort()
        compare(names, ["Chromium", "Firefox"])
    }

    function test_exact_quote_only_returns_all_visible() {
        compare(filter.filterApps(apps, "'").length, 4)
    }

    function test_exact_no_match() {
        compare(filter.filterApps(apps, "'zzzzz").length, 0)
    }

    function test_exact_case_insensitive() {
        compare(filter.filterApps(apps, "'WEB").length, 2)
    }

    function test_exact_does_not_fuzzy_expand() {
        compare(filter.filterApps(apps, "'frfx").length, 0)
    }

    function test_prefix_match() {
        const result = filter.filterApps(apps, "^firefox")
        compare(result.length, 1)
        compare(result[0].name, "Firefox")
    }

    function test_prefix_no_match_mid_string() {
        // "fox" is not at the start of any entry
        compare(filter.filterApps(apps, "^fox").length, 0)
    }

    function test_suffix_match() {
        // Anchors to name, not genericName — "firefox" ends with "fox"... no, test name ending
        compare(filter.filterApps(apps, "eovim$").length, 1)
        compare(filter.filterApps(apps, "eovim$")[0].name, "Neovim")
    }

    function test_suffix_does_not_anchor_to_generic_name() {
        // "Web Browser" is the genericName of Firefox/Chromium; browser$ should NOT match
        // because the name fields are "firefox" and "chromium", neither ends with "browser"
        compare(filter.filterApps(apps, "browser$").length, 0)
    }

    function test_suffix_no_match_mid_string() {
        // "fire" is a prefix of "firefox", not a suffix
        compare(filter.filterApps(apps, "fire$").length, 0)
    }

    function test_negate_fuzzy() {
        const names = filter.filterApps(apps, "!firefox").map(e => e.name).sort()
        compare(names, ["Chromium", "Neovim", "Terminal"])
    }

    function test_negate_exact() {
        const names = filter.filterApps(apps, "!'web").map(e => e.name).sort()
        compare(names, ["Neovim", "Terminal"])
    }

    function test_negate_prefix() {
        const names = filter.filterApps(apps, "!^firefox").map(e => e.name).sort()
        compare(names, ["Chromium", "Neovim", "Terminal"])
    }

    function test_negate_suffix() {
        // Neovim ends with "vim"; negate excludes it
        const names = filter.filterApps(apps, "!vim$").map(e => e.name).sort()
        compare(names, ["Chromium", "Firefox", "Terminal"])
    }

    function test_combined_prefix_and_exact() {
        // Must start with "firefox" AND contain "web"
        const result = filter.filterApps(apps, "^firefox 'web")
        compare(result.length, 1)
        compare(result[0].name, "Firefox")
    }

    function test_nodisplay_excluded_even_when_query_matches() {
        const fixture = [
            { name: "Visible",     genericName: "", noDisplay: false },
            { name: "HiddenMatch", genericName: "", noDisplay: true  },
        ]
        compare(filter.filterApps(fixture, "hidden").length, 0)
    }
}

// ── ExecPrep ──────────────────────────────────────────────────────────────────

TestCase {
    name: "ExecPrep"

    ExecPrep { id: exec }

    function test_strip_percent_u()  { compare(exec.stripExecCodes("firefox %u"),  "firefox") }
    function test_strip_percent_U()  { compare(exec.stripExecCodes("app %U"),       "app") }
    function test_strip_percent_f()  { compare(exec.stripExecCodes("gimp %f"),      "gimp") }
    function test_strip_percent_F()  { compare(exec.stripExecCodes("app %F"),       "app") }
    function test_strip_percent_d()  { compare(exec.stripExecCodes("app %d"),       "app") }
    function test_strip_percent_D()  { compare(exec.stripExecCodes("app %D"),       "app") }
    function test_strip_percent_n()  { compare(exec.stripExecCodes("app %n"),       "app") }
    function test_strip_percent_N()  { compare(exec.stripExecCodes("app %N"),       "app") }
    function test_strip_percent_i()  { compare(exec.stripExecCodes("app %i"),       "app") }
    function test_strip_percent_c()  { compare(exec.stripExecCodes("app %c"),       "app") }
    function test_strip_percent_k()  { compare(exec.stripExecCodes("app %k"),       "app") }
    function test_strip_percent_v()  { compare(exec.stripExecCodes("app %v"),       "app") }
    function test_strip_percent_m()  { compare(exec.stripExecCodes("app %m"),       "app") }
    function test_strip_percent_pct(){ compare(exec.stripExecCodes("app %%"),       "app") }

    function test_strip_multiple_codes() {
        compare(exec.stripExecCodes("app %i %c %k %u"), "app")
    }

    function test_plain_exec_unchanged() {
        compare(exec.stripExecCodes("firefox --new-window"), "firefox --new-window")
    }

    function test_null_exec_string()      { compare(exec.stripExecCodes(null),      "") }
    function test_undefined_exec_string() { compare(exec.stripExecCodes(undefined), "") }

    function test_does_not_strip_unknown_codes() {
        compare(exec.stripExecCodes("app %z"), "app %z")
    }

    function test_no_terminal_direct_exec() {
        compare(exec.buildExec({ execString: "firefox %u", runInTerminal: false }, "kitty"), "firefox")
    }

    function test_terminal_wraps_exec() {
        compare(exec.buildExec({ execString: "nvim %f", runInTerminal: true }, "kitty"), "kitty -- nvim")
    }

    function test_terminal_wraps_exec_with_args() {
        compare(exec.buildExec({ execString: "nvim --noplugin %f", runInTerminal: true }, "kitty"), "kitty -- nvim --noplugin")
    }

    function test_workspace_prefix_format() {
        compare(exec.workspaceExec({ execString: "firefox %u", runInTerminal: false }, 3, "kitty"), "[workspace 3] firefox")
    }

    function test_workspace_with_terminal() {
        compare(exec.workspaceExec({ execString: "nvim %f", runInTerminal: true }, 1, "kitty"), "[workspace 1] kitty -- nvim")
    }

    function test_workspace_number_embedded() {
        verify(exec.workspaceExec({ execString: "app", runInTerminal: false }, 5, "kitty").startsWith("[workspace 5]"))
    }
}

} // Item
