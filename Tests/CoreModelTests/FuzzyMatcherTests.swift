import Foundation
import Testing

import CerebralCore

/// NIC-168: deterministic lexical matching tiers for command suggestions.

// MARK: - Tier ordering

@Test("tiers rank exact > prefix > word prefix > subsequence > edit distance")
func tierOrdering() {
    let exact = FuzzyMatcher.score(query: "chrome", candidate: "chrome")
    let prefix = FuzzyMatcher.score(query: "chro", candidate: "chrome")
    let wordPrefix = FuzzyMatcher.score(query: "chrome", candidate: "google chrome")
    let subsequence = FuzzyMatcher.score(query: "chrme", candidate: "chrome")
    let typo = FuzzyMatcher.score(query: "serach", candidate: "search")

    #expect(exact == 1.0)
    #expect(prefix != nil && wordPrefix != nil && subsequence != nil && typo != nil)
    #expect(prefix! < exact!)
    #expect(wordPrefix! < prefix!)
    #expect(subsequence! < wordPrefix!)
    #expect(typo! < subsequence!)
}

@Test("longer coverage of the candidate ranks higher within a tier")
func coverageBonus() {
    let longer = FuzzyMatcher.score(query: "goog", candidate: "google")
    let shorter = FuzzyMatcher.score(query: "go", candidate: "google")

    #expect(longer != nil && shorter != nil)
    #expect(longer! > shorter!)
}

// MARK: - Typo tolerance

@Test("adjacent transposition is one edit (serach → search, mdoe → mode)")
func transpositions() {
    #expect(FuzzyMatcher.score(query: "serach", candidate: "search") == 0.40)
    #expect(FuzzyMatcher.score(query: "mdoe", candidate: "mode") == 0.40)
}

@Test("the edit budget scales with query length")
func editBudget() {
    // 4 typed chars allow one edit — two is a miss.
    #expect(FuzzyMatcher.score(query: "mzdx", candidate: "mode") == nil)
    // 6 typed chars allow two edits.
    #expect(FuzzyMatcher.score(query: "serrch", candidate: "search") != nil)
    // Unrelated strings never match.
    #expect(FuzzyMatcher.score(query: "abcdefgh", candidate: "12345678") == nil)
}

// MARK: - Short-query guards

@Test("one or two characters only match as a prefix, never loosely")
func shortQueryGuards() {
    // Prefix is fine at any length.
    #expect(FuzzyMatcher.score(query: "o", candidate: "open") != nil)
    // "oe" is a subsequence of "note", but two characters are noise — no match.
    #expect(FuzzyMatcher.score(query: "oe", candidate: "note") == nil)
    // Two characters also get no edit-distance budget.
    #expect(FuzzyMatcher.score(query: "rn", candidate: "run") == nil)
}

// MARK: - Normalization

@Test("matching folds case, diacritics, and whitespace runs")
func normalization() {
    #expect(FuzzyMatcher.score(query: "CAFÉ", candidate: "cafe") == 1.0)
    #expect(FuzzyMatcher.score(query: "  google   chrome ", candidate: "Google Chrome") == 1.0)
}

@Test("a multi-word query can start at a later word boundary")
func multiWordWordPrefix() {
    let score = FuzzyMatcher.score(query: "studio code", candidate: "visual studio code")

    #expect(score != nil)
    // Word-boundary band, not the looser subsequence band.
    #expect(score! >= 0.7)
}

@Test("empty inputs never match")
func emptyInputs() {
    #expect(FuzzyMatcher.score(query: "", candidate: "open") == nil)
    #expect(FuzzyMatcher.score(query: "open", candidate: "") == nil)
}
