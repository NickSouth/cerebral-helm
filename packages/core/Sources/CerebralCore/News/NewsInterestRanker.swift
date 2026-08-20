import Foundation

/// Sorts a profile's candidate headlines so the ones matching the user's interests reach the panel
/// first (NIC-223).
///
/// The panel has four slots and the providers hand back roughly ten candidates, so the question is
/// which four. This **ranks** rather than filters: matched headlines sort to the top and the
/// remaining slots are backfilled with the best unmatched ones, so a narrow interest on a quiet news
/// day can never leave the panel emptier than it was before interests existed. The cap itself stays
/// where it has always been, in the event mapping.
///
/// Only ``NewsHeadline/title`` is matched. It is the only text the contract carries — there is no
/// body or summary — and matching the source name would rank a whole publisher up rather than a
/// story.
///
/// Matching is case-insensitive. A phrase interest (quoted, or simply more than one word) must
/// appear contiguously; a single-word interest matches on word boundaries, so `AI` does not match
/// `said` and `EU` does not match `queue`. The score is the number of **distinct** interests a
/// headline matches, so one headline hitting three separate interests outranks one hitting a single
/// interest three times.
public enum NewsInterestRanker {
    /// Interest-matched headlines first, everything else after, both in their original order.
    ///
    /// The sort is **stable**: within a score band the providers' own ordering survives, which is
    /// what preserves the RSS fallback's round-robin source diversity and NewsData's own relevance
    /// order. No interests (or no matches at all) returns the input untouched — the pre-NIC-223
    /// behaviour, reached without a special case.
    public static func rank(_ headlines: [NewsHeadline], by interests: [NewsInterest]) -> [NewsHeadline] {
        guard !interests.isEmpty, headlines.count > 1 else { return headlines }
        // Swift's sort is not guaranteed stable, so the original index is carried as the tiebreak
        // rather than trusted.
        var ranked: [(index: Int, score: Int, headline: NewsHeadline)] = []
        ranked.reserveCapacity(headlines.count)
        for (index, headline) in headlines.enumerated() {
            ranked.append((index, score(headline, against: interests), headline))
        }
        ranked.sort { left, right in
            left.score == right.score ? left.index < right.index : left.score > right.score
        }
        return ranked.map(\.headline)
    }

    /// How many distinct interests a headline matches.
    static func score(_ headline: NewsHeadline, against interests: [NewsInterest]) -> Int {
        let title = headline.title.lowercased()
        return interests.reduce(into: 0) { total, interest in
            if matches(interest, inLowercasedTitle: title) { total += 1 }
        }
    }

    /// Whether one interest appears in an already-lowercased title.
    static func matches(_ interest: NewsInterest, inLowercasedTitle title: String) -> Bool {
        let term = interest.term.lowercased()
        guard !term.isEmpty else { return false }
        return interest.isPhrase ? title.contains(term) : containsWord(term, in: title)
    }

    /// Substring search that additionally requires both edges to fall on a word boundary.
    ///
    /// Written as a scan rather than a regular expression so the rule stays obvious and the cost
    /// stays proportional to the title: a headline is a dozen words, and this runs once per interest
    /// per headline on every emit.
    static func containsWord(_ needle: String, in haystack: String) -> Bool {
        var searchStart = haystack.startIndex
        while let range = haystack.range(of: needle, range: searchStart..<haystack.endIndex) {
            let openEdge = range.lowerBound == haystack.startIndex
                || !isWordCharacter(haystack[haystack.index(before: range.lowerBound)])
            let closeEdge = range.upperBound == haystack.endIndex
                || !isWordCharacter(haystack[range.upperBound])
            if openEdge && closeEdge { return true }
            // Advance one character, not past the whole match: an earlier occurrence failing its
            // boundary test says nothing about a later one.
            searchStart = haystack.index(after: range.lowerBound)
        }
        return false
    }

    /// Letters and digits bind into a word; punctuation, whitespace and symbols break it — which is
    /// what lets a hyphenated or possessive term match the way a reader expects.
    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber
    }
}
