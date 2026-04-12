// App list filtering for kh-launcher.
// Mirrors the filteredApps computed property in kh-launcher.nix.
import QtQuick
import "."

Item {
    FuzzyScore { id: _fuzzy }

    // apps: array of { name, genericName, noDisplay }
    // searchText: raw text from the search field
    // Returns a filtered, sorted array.
    //
    // fzf-style query syntax — space-separated tokens are AND'd:
    //   foo    fuzzy match
    //   'foo   exact substring match
    //   ^foo   prefix match
    //   foo$   suffix match
    //   !foo   negate (composes: !'foo  !^foo  !foo$)
    function filterApps(apps, searchText) {
        const all = apps.filter(e => !e.noDisplay)
            .sort((a, b) => a.name.localeCompare(b.name))
        const terms = _parseTerms(searchText)
        if (terms.length === 0) return all
        const matches = []
        for (const e of all) {
            const name = e.name.toLowerCase()
            const haystack = (e.name + (e.genericName ? " " + e.genericName : ""))
                .toLowerCase()
            if (terms.every(t => _matchTerm(t, name, haystack))) matches.push(e)
        }
        return matches
    }

    function _parseTerms(searchText) {
        const terms = []
        for (const token of searchText.toLowerCase().trim().split(/\s+/)) {
            if (!token) continue
            let rest = token
            const negate = rest.startsWith("!")
            if (negate) rest = rest.slice(1)
            let type, needle
            if (rest.startsWith("'")) {
                type = "exact"; needle = rest.slice(1)
            } else if (rest.startsWith("^")) {
                type = "prefix"; needle = rest.slice(1)
            } else if (rest.endsWith("$")) {
                type = "suffix"; needle = rest.slice(0, -1)
            } else {
                type = "fuzzy"; needle = rest
            }
            if (needle) terms.push({ type, needle, negate })
        }
        return terms
    }

    // name: app name only (for anchored matches)
    // haystack: name + genericName (for fuzzy/exact matches)
    function _matchTerm(term, name, haystack) {
        let matched
        switch (term.type) {
        case "exact":  matched = haystack.includes(term.needle); break
        case "prefix": matched = name.startsWith(term.needle); break
        case "suffix": matched = name.endsWith(term.needle); break
        default:       matched = _fuzzy.fuzzyScore(term.needle, haystack) >= 0; break
        }
        return term.negate ? !matched : matched
    }
}
