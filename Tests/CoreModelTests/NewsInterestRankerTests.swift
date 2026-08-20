import Foundation
import Testing

// `score`/`matches` are internal implementation detail exercised directly, hence `@testable`.
@testable import CerebralCore

/// NIC-223: interest-matched headlines sort to the top of a profile's candidates so the panel's four
/// slots go to the stories the user cares about — ranking, never filtering, so the panel is never
/// emptier than it was before interests existed.

private func newsRankerHeadline(_ id: String, _ title: String) -> NewsHeadline {
    NewsHeadline(id: id, title: title, source: "Wire", url: "https://ex.com/\(id)")
}

private let newsRankerCandidates = [
    newsRankerHeadline("a", "Storm warning issued for the coast"),
    newsRankerHeadline("b", "OpenAI ships new reasoning model"),
    newsRankerHeadline("c", "Markets close mixed on earnings"),
    newsRankerHeadline("d", "Fed holds interest rates steady"),
]

@Test("matched headlines sort ahead of unmatched, and the unmatched still backfill behind them")
func newsRankerSortsMatchesFirstAndKeepsTheRest() {
    let ranked = NewsInterestRanker.rank(newsRankerCandidates, by: [
        NewsInterest(term: "OpenAI"),
        NewsInterest(term: "interest rates", isPhrase: true),
    ])
    #expect(ranked.map(\.id) == ["b", "d", "a", "c"])
    // Nothing is dropped: the panel's cap is applied downstream, by the event mapping.
    #expect(ranked.count == newsRankerCandidates.count)
}

@Test("a single match still leaves a full list, so a narrow interest cannot empty the panel")
func newsRankerBackfillsBehindASingleMatch() {
    let ranked = NewsInterestRanker.rank(newsRankerCandidates, by: [NewsInterest(term: "OpenAI")])
    #expect(ranked.first?.id == "b")
    #expect(ranked.map(\.id) == ["b", "a", "c", "d"])
}

@Test("a headline matching more distinct interests outranks one matching fewer")
func newsRankerScoresByDistinctInterests() {
    let ranked = NewsInterestRanker.rank(
        [
            newsRankerHeadline("one", "Apple ships a new laptop"),
            newsRankerHeadline("two", "Apple and Swift developers respond"),
        ],
        by: [NewsInterest(term: "Apple"), NewsInterest(term: "Swift")]
    )
    #expect(ranked.map(\.id) == ["two", "one"])
}

@Test("no interests, or no matches at all, leaves the providers' own order untouched")
func newsRankerIsANoOpWithoutMatches() {
    #expect(NewsInterestRanker.rank(newsRankerCandidates, by: []).map(\.id) == ["a", "b", "c", "d"])
    let unmatched = NewsInterestRanker.rank(newsRankerCandidates, by: [NewsInterest(term: "cricket")])
    #expect(unmatched.map(\.id) == ["a", "b", "c", "d"])
}

@Test("ties keep the source order, preserving the fallback's round-robin publisher diversity")
func newsRankerIsStableWithinAScoreBand() {
    let candidates = (0..<12).map { newsRankerHeadline("h\($0)", $0 % 2 == 0 ? "Swift news \($0)" : "Other \($0)") }
    let ranked = NewsInterestRanker.rank(candidates, by: [NewsInterest(term: "Swift")])
    #expect(ranked.prefix(6).map(\.id) == ["h0", "h2", "h4", "h6", "h8", "h10"])
    #expect(ranked.suffix(6).map(\.id) == ["h1", "h3", "h5", "h7", "h9", "h11"])
}

@Test("a single-word interest matches on word boundaries, not on any substring")
func newsRankerMatchesSingleWordsOnBoundaries() {
    let ai = NewsInterest(term: "AI")
    #expect(NewsInterestRanker.matches(ai, inLowercasedTitle: "the minister said nothing") == false)
    #expect(NewsInterestRanker.matches(ai, inLowercasedTitle: "ai regulation advances") == true)
    #expect(NewsInterestRanker.matches(ai, inLowercasedTitle: "the eu debates ai.") == true)
    #expect(NewsInterestRanker.matches(ai, inLowercasedTitle: "\"ai\" is the word of the year") == true)
    // An earlier non-boundary occurrence must not hide a later real one.
    #expect(NewsInterestRanker.matches(ai, inLowercasedTitle: "said that ai wins") == true)
}

@Test("a phrase interest must appear contiguously")
func newsRankerMatchesPhrasesContiguously() {
    let phrase = NewsInterest(term: "open source", isPhrase: true)
    #expect(NewsInterestRanker.matches(phrase, inLowercasedTitle: "an open source release") == true)
    #expect(NewsInterestRanker.matches(phrase, inLowercasedTitle: "the source is open") == false)
}

@Test("matching is case-insensitive and reads the title only, never the source name")
func newsRankerMatchesTitlesCaseInsensitively() {
    let headline = NewsHeadline(id: "x", title: "REUTERS wins award", source: "Bloomberg", url: nil)
    #expect(NewsInterestRanker.score(headline, against: [NewsInterest(term: "reuters")]) == 1)
    // The source name is not searched: an interest in a publisher would otherwise rank its whole feed.
    #expect(NewsInterestRanker.score(headline, against: [NewsInterest(term: "Bloomberg")]) == 0)
}
