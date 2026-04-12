// App list filtering for kh-launcher.
// Mirrors the filteredApps computed property in kh-launcher.nix.
import QtQuick
import "."

Item {
    FuzzyScore { id: _fuzzy }

    // apps: array of { name, genericName, noDisplay }
    // searchText: raw text from the search field
    // Returns a filtered, sorted array.
    function filterApps(apps, searchText) {
        const all = apps.filter(e => !e.noDisplay)
            .sort((a, b) => a.name.localeCompare(b.name))
        const raw = searchText.toLowerCase().replace(/\s+/g, "")
        if (!raw) return all
        const exact = raw.startsWith("'")
        const needle = exact ? raw.slice(1) : raw
        if (!needle) return all

        const matches = []
        for (const e of all) {
            const haystack = (e.name + (e.genericName ? " " + e.genericName : ""))
                .toLowerCase().replace(/\s+/g, "")
            if (exact) {
                if (haystack.includes(needle)) matches.push(e)
            } else {
                if (_fuzzy.fuzzyScore(needle, haystack) >= 0) matches.push(e)
            }
        }
        return matches
    }
}
