// Fuzzy subsequence scorer used by kh-launcher and kh-cliphist.
// Returns score >= 0 on match, -1 on no match.
// Callers must lowercase both needle and haystack before calling.
import QtQuick

QtObject {
    function fuzzyScore(needle, haystack) {
        let ni = 0, score = 0, consecutive = 0
        for (let hi = 0; hi < haystack.length && ni < needle.length; hi++) {
            if (needle[ni] === haystack[hi]) {
                ni++
                consecutive++
                score += consecutive
                if (hi === 0 || !/\w/.test(haystack[hi - 1])) score += 5
            } else {
                consecutive = 0
            }
        }
        return ni === needle.length ? score : -1
    }
}
