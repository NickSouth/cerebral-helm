import Foundation

/// Builds the boolean keyword query a metered news provider searches with, from the user's
/// interests for one relevance profile (NIC-223).
///
/// Category filtering alone is coarse — `technology` covers every consumer-gadget blog — so the
/// interests are also asked *of the source*, not only applied to what it happens to return. The
/// terms are OR-joined so any one of them qualifies an article: an AND query would ask for a story
/// about artificial intelligence **and** rugby, which is not what a list of interests means.
///
/// ## The length cap is 100, and that is measured, not documented
///
/// NewsData's own guidance says a query may run to 512 characters. The live endpoint rejects
/// anything past **100** with `422 Query length cannot be greater than 100`, counting the raw
/// string — quotes, spaces and operators included — before URL encoding. The API wins over its
/// documentation, so ``maximumLength`` is 100 and terms that do not fit are dropped rather than
/// spending a request on a query that will be refused.
///
/// Terms are considered in the note's own order, which is its priority order. A term too long to
/// fit is **skipped** rather than ending the query: a later, shorter interest still deserves its
/// place, and skipping never promotes it above a higher-priority term that did fit.
///
/// No parentheses: `a OR b` and `(a OR b)` behave identically on the endpoint (measured), and with
/// a 100-character budget two characters are better spent on a term.
public enum NewsInterestQuery {
    /// The provider's hard limit on a query, in characters of the raw (unencoded) string.
    public static let maximumLength = 100

    /// Words that are query syntax rather than search terms, so a term equal to one must be quoted
    /// or it changes the meaning of the query it sits in.
    private static let operatorKeywords: Set<String> = ["and", "or", "not"]

    /// The `q` value for one profile's interests, or nil when there is nothing to ask for — in
    /// which case the caller omits the parameter entirely and the request is byte-identical to the
    /// pre-NIC-223 one.
    public static func build(_ interests: [NewsInterest], limit: Int = maximumLength) -> String? {
        var parts: [String] = []
        var length = 0
        for interest in interests {
            guard let rendered = render(interest.term) else { continue }
            // Every term after the first also pays for the " OR " that joins it.
            let cost = parts.isEmpty ? rendered.count : rendered.count + 4
            guard length + cost <= limit else { continue }
            parts.append(rendered)
            length += cost
        }
        return parts.isEmpty ? nil : parts.joined(separator: " OR ")
    }

    /// One term as it appears in the query: sanitized, and quoted only when it has to be.
    ///
    /// Quoting costs two characters against a tight budget, so a plain single word goes in bare.
    /// A term containing anything else — a space, punctuation — must be quoted to stay one term,
    /// and a term that *is* an operator keyword must be quoted so it is searched for rather than
    /// obeyed.
    static func render(_ term: String) -> String? {
        let sanitized = sanitize(term)
        guard !sanitized.isEmpty else { return nil }
        return needsQuoting(sanitized) ? "\"\(sanitized)\"" : sanitized
    }

    /// Strips the characters that are query syntax and collapses whitespace.
    ///
    /// Quotes, parentheses and backslashes are removed rather than escaped: they cannot appear in a
    /// term without changing how the query parses, and a search term is not the place to be clever
    /// about escaping rules the provider has not documented.
    static func sanitize(_ term: String) -> String {
        let stripped = term.filter { !"\"()\\".contains($0) }
        return stripped.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func needsQuoting(_ term: String) -> Bool {
        if operatorKeywords.contains(term.lowercased()) { return true }
        return term.contains { character in
            !(character.isLetter || character.isNumber || character == "-" || character == "'")
        }
    }
}
