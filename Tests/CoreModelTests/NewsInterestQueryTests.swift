import Foundation
import Testing

// `render`/`sanitize` are internal helpers exercised directly, hence `@testable`.
@testable import CerebralCore

/// NIC-223: the interest terms asked *of* the metered provider as a `q=` search, not only applied to
/// what it returns. The 100-character cap is the live endpoint's, measured — the vendor's own
/// documentation says 512 and the API answers 422.

@Test("terms are OR-joined in the note's priority order")
func newsQueryJoinsTermsWithOR() {
    let query = NewsInterestQuery.build([
        NewsInterest(term: "artificial intelligence", isPhrase: true),
        NewsInterest(term: "big tech", isPhrase: true),
        NewsInterest(term: "rugby"),
    ])
    #expect(query == "\"artificial intelligence\" OR \"big tech\" OR rugby")
}

@Test("a plain single word goes in bare; anything else is quoted to stay one term")
func newsQueryQuotesOnlyWhatItMustAndKeepsOperatorsSafe() {
    #expect(NewsInterestQuery.render("rugby") == "rugby")
    #expect(NewsInterestQuery.render("mid-terms") == "mid-terms")
    #expect(NewsInterestQuery.render("Ardern's") == "Ardern's")
    // A space is what makes a term more than one token, so it has to be quoted to stay one.
    #expect(NewsInterestQuery.render("Ardern's cabinet") == "\"Ardern's cabinet\"")
    #expect(NewsInterestQuery.render("computer science") == "\"computer science\"")
    #expect(NewsInterestQuery.render("A.I.") == "\"A.I.\"")
    // A term that *is* an operator must be searched for, not obeyed.
    #expect(NewsInterestQuery.render("not") == "\"not\"")
    #expect(NewsInterestQuery.render("OR") == "\"OR\"")
}

@Test("query syntax inside a term is stripped rather than escaped, and whitespace collapses")
func newsQuerySanitizesTerms() {
    #expect(NewsInterestQuery.sanitize("say \"hello\"") == "say hello")
    #expect(NewsInterestQuery.sanitize("(grouped)") == "grouped")
    #expect(NewsInterestQuery.sanitize("  spaced\tout\nterm  ") == "spaced out term")
    // Nothing usable left is no term at all, not an empty quoted string.
    #expect(NewsInterestQuery.render("\"\"()") == nil)
}

@Test("no interests means no query at all, so the request stays byte-identical to before")
func newsQueryIsNilWithoutUsableTerms() {
    #expect(NewsInterestQuery.build([]) == nil)
    #expect(NewsInterestQuery.build([NewsInterest(term: "   ")]) == nil)
}

@Test("the query never exceeds the provider's 100-character cap")
func newsQueryRespectsTheLengthCap() {
    let interests = (0..<40).map { NewsInterest(term: "interest number \($0)", isPhrase: true) }
    let query = try? #require(NewsInterestQuery.build(interests))
    #expect((query?.count ?? .max) <= NewsInterestQuery.maximumLength)
    #expect(query?.hasPrefix("\"interest number 0\" OR \"interest number 1\"") == true)
}

@Test("a term too long to fit is skipped, and shorter later terms still get their place")
func newsQuerySkipsOversizedTermsWithoutEndingTheQuery() {
    let query = NewsInterestQuery.build(
        [
            NewsInterest(term: "rugby"),
            NewsInterest(term: String(repeating: "x", count: 200)),
            NewsInterest(term: "Dune"),
        ],
        limit: 40
    )
    // Skipping preserves priority order — it never promotes a later term above one that fit.
    #expect(query == "rugby OR Dune")
}

@Test("the cap counts the joining operators, not just the terms")
func newsQueryChargesForTheJoiners() {
    let two = [NewsInterest(term: "aaaa"), NewsInterest(term: "bbbb")]
    #expect(NewsInterestQuery.build(two, limit: 12) == "aaaa OR bbbb")   // 4 + 4 + 4
    #expect(NewsInterestQuery.build(two, limit: 11) == "aaaa")           // the joiner no longer fits
}
