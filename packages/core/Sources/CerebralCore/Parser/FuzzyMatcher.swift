import Foundation

/// Deterministic lexical matching for command suggestions (NIC-168).
///
/// Scores how closely a typed query matches a candidate string (a reference id,
/// label, or verb) using fixed, non-overlapping bands so ordering is stable and
/// explainable — no model, no locale-dependent heuristics:
///
/// - `1.0`        exact (normalized) match
/// - `0.85–0.95`  candidate starts with the query
/// - `0.70–0.80`  a later word of the candidate starts with the query
/// - `0.50–0.60`  the query is an in-order subsequence of the candidate
/// - `0.30–0.40`  within a small edit distance (typos: substitutions, adjacent
///                transpositions, insertions, deletions)
///
/// Within the prefix/word-prefix/subsequence bands, longer coverage of the
/// candidate scores higher (`goog` beats `go` for "google"). The edit-distance
/// budget scales with query length (≤4 chars: 1 edit · ≤8: 2 · longer: 3), and
/// the loose tiers (subsequence, edit distance) require at least 3 typed
/// characters so one or two keystrokes never match on noise.
public enum FuzzyMatcher {
    /// Lowercases, strips diacritics, trims, and collapses runs of whitespace —
    /// the one normalization every comparison shares.
    public static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    /// The match score for `query` against `candidate`, or nil when they do not
    /// match under any tier. Both inputs are normalized internally.
    public static func score(query: String, candidate: String) -> Double? {
        let query = normalize(query)
        let candidate = normalize(candidate)
        guard !query.isEmpty, !candidate.isEmpty else { return nil }

        if query == candidate {
            return 1.0
        }

        let coverage = min(1.0, Double(query.count) / Double(candidate.count))
        if candidate.hasPrefix(query) {
            return 0.85 + 0.1 * coverage
        }
        if wordStartsWithQuery(query: query, candidate: candidate) {
            return 0.7 + 0.1 * coverage
        }
        // Loose tiers: too few characters to distinguish intent from noise.
        guard query.count >= 3 else { return nil }
        if query.count <= candidate.count, isSubsequence(query: query, candidate: candidate) {
            return 0.5 + 0.1 * coverage
        }
        let budget = editBudget(queryLength: query.count)
        if let distance = boundedEditDistance(query, candidate, limit: budget) {
            return 0.45 - 0.05 * Double(distance)
        }
        return nil
    }

    // MARK: - Tiers

    /// The candidate, read from a word boundary other than the start, begins with
    /// the query ("chrome" → "google chrome", "studio code" → "visual studio code").
    /// Starting at the first word is the plain-prefix tier's job.
    private static func wordStartsWithQuery(query: String, candidate: String) -> Bool {
        let words = candidate.split(separator: " ")
        return (1..<words.count).contains { start in
            words[start...].joined(separator: " ").hasPrefix(query)
        }
    }

    private static func isSubsequence(query: String, candidate: String) -> Bool {
        var remainder = candidate[...]
        for character in query {
            guard let found = remainder.firstIndex(of: character) else { return false }
            remainder = remainder[remainder.index(after: found)...]
        }
        return true
    }

    /// Allowed typo budget by typed length: short queries get one edit, medium
    /// two, long three. Fixed steps keep ranking deterministic and explainable.
    private static func editBudget(queryLength: Int) -> Int {
        if queryLength <= 4 { return 1 }
        if queryLength <= 8 { return 2 }
        return 3
    }

    /// Optimal-string-alignment distance (Levenshtein plus adjacent
    /// transposition, so "serach" → "search" is one edit), abandoning early once
    /// every alignment exceeds `limit`. Returns nil when the distance is over
    /// the limit.
    private static func boundedEditDistance(_ left: String, _ right: String, limit: Int) -> Int? {
        let a = Array(left)
        let b = Array(right)
        // A length gap alone exceeding the budget can never come back under it.
        guard abs(a.count - b.count) <= limit else { return nil }

        var twoAgo = [Int](repeating: 0, count: b.count + 1)
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)

        for i in 1...a.count {
            current[0] = i
            var rowMinimum = current[0]
            for j in 1...b.count {
                let substitution = previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1)
                var best = min(previous[j] + 1, current[j - 1] + 1, substitution)
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    best = min(best, twoAgo[j - 2] + 1)
                }
                current[j] = best
                rowMinimum = min(rowMinimum, best)
            }
            if rowMinimum > limit { return nil }
            (twoAgo, previous, current) = (previous, current, twoAgo)
        }
        let distance = previous[b.count]
        return distance <= limit ? distance : nil
    }
}
