import Foundation

/// One search term the News panel treats as relevant, plus the human context that explains why it
/// is there (NIC-223).
///
/// `context` is parsed and carried but is deliberately **not** matched against: it is prose written
/// for the reader — and for a future knowledge-base cleaning pass that revises the note as interests
/// drift — and folding it into matching would dilute a precise term with the sentence around it.
///
/// `isPhrase` records that the term must match contiguously rather than as a bare word: an author
/// writes `"interest rates"` (or simply a multi-word term) when the words only mean something
/// together. A single-word term matches on word boundaries instead, so `AI` cannot match `said`.
public struct NewsInterest: Equatable, Sendable {
    /// The search term, with Markdown emphasis and quoting removed.
    public let term: String
    /// The author's note on why this interest matters; nil when the item carried none.
    public let context: String?
    /// True when the term must match as a contiguous phrase (quoted, or more than one word).
    public let isPhrase: Bool

    public init(term: String, context: String? = nil, isPhrase: Bool = false) {
        self.term = term
        self.context = context
        self.isPhrase = isPhrase
    }
}

/// The user's "News Interests" note, parsed from Markdown in the knowledge vault (NIC-223).
///
/// The note — not config, and not code — is the relevance lever for the News panel. NewsData's
/// categories are coarse (`technology` covers every consumer gadget blog), so the panel needs to
/// know what *this* user cares about. Keeping that in the vault rather than in `config/` means it is
/// user-owned, hand-editable in any Markdown editor, and safely rewritable later by a knowledge-base
/// cleaning pass as interests shift.
///
/// ## The layout
///
/// ```markdown
/// ## Executive
///
/// - **artificial intelligence** — the industry I work in; funding, regulation, big-lab releases
/// - **"interest rates"** — affects the mortgage
///
/// ## Any mode
///
/// - **New Zealand** — home
/// ```
///
/// A `##` heading names a **mode** (its id or its label, case-insensitively); the bullets directly
/// under it are that mode's interests. `## Any mode` (or `All modes` / `Global`) is the reserved
/// shared section merged into every profile. Any other heading level — the note's own `#` title, or
/// a `###` sub-heading — ends the current section, so only bullets sitting directly under a mode
/// heading are read as terms; everything else in the note is free prose.
///
/// Parsing is total: an unknown heading, a nested bullet, a fenced code block, an item with no
/// context, or a note that is missing entirely all degrade to "fewer interests", never to an error.
/// No interests at all means the panel behaves exactly as it did before this note existed.
public struct NewsInterestNote: Equatable, Sendable {
    /// Normalized `##` heading → the interests listed under it, in authored order. The key is the
    /// heading lowercased and trimmed; authored order is preserved because it is the note's own
    /// statement of priority.
    public let sections: [String: [NewsInterest]]

    public init(sections: [String: [NewsInterest]] = [:]) {
        self.sections = sections
    }

    /// The note's filename. This is the contract: the note is found by name, so it may be filed
    /// anywhere in the vault (triage moves notes between folders) but may not be renamed.
    public static let filename = "news-interests.md"

    /// Where the note is documented to live. Checked first, so the common case costs one stat
    /// rather than a tree walk.
    public static let preferredRelativePath = "reference/news-interests.md"

    /// Headings that mean "every mode" rather than one named mode, lowercased.
    public static let sharedSectionAliases: Set<String> = ["any mode", "all modes", "any", "all", "global"]

    // MARK: - Resolution

    /// Folds the note's mode-keyed sections into the `newsProfile` keys the news pipeline actually
    /// runs on (NIC-223).
    ///
    /// `modeProfiles` maps a mode's id **and** its label (both lowercased) to that mode's
    /// `newsProfile`, so the author may head a section `## Executive` or `## executive` and either
    /// resolves. Two modes sharing one profile have their terms unioned; the shared section is
    /// appended to every profile after the mode-specific terms, because the note's order is its
    /// priority order and a term chosen for this mode outranks one chosen for all of them.
    /// Duplicates (case-insensitively, by term) collapse to their first occurrence.
    ///
    /// A heading matching no mode is ignored: the note is user prose, so an extra section is a
    /// normal thing to find, not a fault to report.
    public func resolve(modeProfiles: [String: String]) -> [String: [NewsInterest]] {
        var lookup: [String: String] = [:]
        for (mode, profile) in modeProfiles {
            lookup[Self.normalizeHeading(mode)] = profile
        }

        var resolved: [String: [NewsInterest]] = [:]
        // Sorted so the union of two modes sharing a profile is deterministic run to run.
        for heading in sections.keys.sorted() {
            guard let profile = lookup[heading], let interests = sections[heading] else { continue }
            resolved[profile, default: []].append(contentsOf: interests)
        }

        let shared = sections.first { Self.sharedSectionAliases.contains($0.key) }?.value ?? []
        if !shared.isEmpty {
            for profile in Set(modeProfiles.values) {
                resolved[profile, default: []].append(contentsOf: shared)
            }
        }

        return resolved.mapValues(Self.deduplicated)
    }

    /// Keeps the first occurrence of each term, compared case-insensitively.
    private static func deduplicated(_ interests: [NewsInterest]) -> [NewsInterest] {
        var seen = Set<String>()
        return interests.filter { seen.insert($0.term.lowercased()).inserted }
    }

    // MARK: - Parsing

    /// Parses the note's Markdown. Never throws: see the type's note on total parsing.
    public static func parse(_ markdown: String) -> NewsInterestNote {
        var sections: [String: [NewsInterest]] = [:]
        var heading: String?
        var inFence = false

        for line in body(of: markdown) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // A fenced block is illustrative, not authoritative — a documented example of the
            // layout inside the note must not inject its own sample terms.
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                inFence.toggle()
                continue
            }
            if inFence { continue }

            if trimmed.hasPrefix("#") {
                heading = modeHeading(from: trimmed)
                continue
            }

            guard
                let heading,
                let item = listItem(from: line),
                let interest = interest(from: item)
            else { continue }
            sections[heading, default: []].append(interest)
        }

        return NewsInterestNote(sections: sections)
    }

    /// The note's lines with any leading YAML frontmatter block removed. The block is skipped by
    /// line scan rather than parsed: nothing here reads frontmatter, and a hand-rolled skip keeps
    /// this type Foundation-only — the YAML parser lives in the knowledge package, which the news
    /// pipeline does not (and should not) depend on.
    private static func body(of markdown: String) -> [Substring] {
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.hasSuffix("\r") ? $0.dropLast() : $0 }
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return lines }
        guard let close = lines.dropFirst().firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces) == "---"
        }) else {
            // An unterminated block is malformed frontmatter, not a note body: reading it as content
            // would turn `title: …` lines into prose. Nothing to parse.
            return []
        }
        return Array(lines[lines.index(after: close)...])
    }

    /// The normalized mode name for a `##` heading, or nil for every other heading level.
    ///
    /// Only `##` names a mode. A `#` title or a `###` sub-heading returns nil, which **ends** the
    /// current section — bullets under a sub-heading are elaboration, not terms.
    private static func modeHeading(from trimmed: String) -> String? {
        let hashes = trimmed.prefix { $0 == "#" }.count
        guard hashes == 2 else { return nil }
        let text = trimmed.dropFirst(hashes).trimmingCharacters(in: .whitespaces)
        let normalized = normalizeHeading(stripInlineMarkup(text))
        return normalized.isEmpty ? nil : normalized
    }

    private static func normalizeHeading(_ heading: String) -> String {
        heading.trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// The content of a **top-level** list item, or nil when the line is not one.
    ///
    /// Indentation is what separates a term from a note about a term: a nested bullet is the
    /// author elaborating, so only items at the left margin (up to one space of slop) are read.
    private static func listItem(from line: Substring) -> String? {
        let indent = line.prefix { $0 == " " || $0 == "\t" }
        guard indent.count <= 1, !indent.contains("\t") else { return nil }
        let rest = line.dropFirst(indent.count)
        guard let marker = rest.first, marker == "-" || marker == "*" || marker == "+" else { return nil }
        let content = rest.dropFirst()
        guard content.first == " " || content.first == "\t" else { return nil }
        return content.trimmingCharacters(in: .whitespaces)
    }

    /// Splits one list item into its term and the context after the dash.
    private static func interest(from item: String) -> NewsInterest? {
        let (rawTerm, rawContext) = split(item)
        let stripped = stripInlineMarkup(rawTerm).trimmingCharacters(in: .whitespaces)

        // A quoted term is the author saying "these words only mean something together".
        var term = stripped
        var quoted = false
        if term.count > 2, term.hasPrefix("\""), term.hasSuffix("\"") {
            term = String(term.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
            quoted = true
        }
        guard !term.isEmpty else { return nil }

        let context = rawContext?.trimmingCharacters(in: .whitespaces)
        return NewsInterest(
            term: term,
            context: (context?.isEmpty == false) ? context : nil,
            // Multi-word terms match contiguously whether or not they were quoted: an author who
            // writes `open source` means the pair, and matching the words independently would pull
            // in every article containing "source".
            isPhrase: quoted || term.contains(" ")
        )
    }

    /// Separates a list item at the first term/context divider — an em dash, an en dash, or a
    /// spaced hyphen. All three are offered because all three are what people actually type.
    private static func split(_ item: String) -> (term: String, context: String?) {
        var earliest: (range: Range<String.Index>, separator: String)?
        for separator in ["—", "–", " - "] {
            guard let range = item.range(of: separator) else { continue }
            if earliest == nil || range.lowerBound < earliest!.range.lowerBound {
                earliest = (range, separator)
            }
        }
        guard let earliest else { return (item, nil) }
        return (String(item[..<earliest.range.lowerBound]), String(item[earliest.range.upperBound...]))
    }

    /// Removes the Markdown that decorates a term without changing what the term *is*.
    ///
    /// `[[note|alias]]` and `[text](url)` collapse to their display text, and `**`, `__` and
    /// backticks are dropped wherever they appear — those three are unambiguously markup. A lone
    /// `*` or `_` is only stripped at the edges, because a term may legitimately contain one and
    /// silently rewriting the middle of a search term would be worse than leaving an asterisk in.
    static func stripInlineMarkup(_ text: String) -> String {
        var result = collapseLinks(text)
        for delimiter in ["**", "__", "`"] {
            result = result.replacingOccurrences(of: delimiter, with: "")
        }
        result = result.trimmingCharacters(in: .whitespaces)
        while let first = result.first, first == "*" || first == "_" {
            result = String(result.dropFirst())
        }
        while let last = result.last, last == "*" || last == "_" {
            result = String(result.dropLast())
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    /// Collapses `[[target|alias]]`, `[[target]]` and `[text](url)` to their display text.
    private static func collapseLinks(_ text: String) -> String {
        var result = ""
        var rest = Substring(text)
        while let open = earliestBracket(in: rest) {
            let isWiki = rest[open].count == 2
            let close = isWiki ? "]]" : "]"
            guard let end = rest.range(of: close, range: open.upperBound..<rest.endIndex) else { break }
            result += rest[..<open.lowerBound]
            let inner = rest[open.upperBound..<end.lowerBound]
            // A wikilink's alias sits after the pipe; without one the target is the display text.
            result += inner.split(separator: "|").last.map(String.init) ?? String(inner)
            rest = rest[end.upperBound...]
            // An inline link's `(url)` carries no display text — drop it entirely.
            if !isWiki, rest.first == "(", let paren = rest.firstIndex(of: ")") {
                rest = rest[rest.index(after: paren)...]
            }
        }
        return result + rest
    }

    /// The next link opener, preferring a wikilink when both start at the same place. Taking the
    /// *earliest* (rather than any wikilink first) is what lets the two link styles mix in one line
    /// without the later form swallowing the text before it.
    private static func earliestBracket(in text: Substring) -> Range<Substring.Index>? {
        let wiki = text.range(of: "[[")
        guard let plain = text.range(of: "[") else { return wiki }
        guard let wiki else { return plain }
        return wiki.lowerBound <= plain.lowerBound ? wiki : plain
    }

    // MARK: - Loading

    /// Loads the note from the effective knowledge root, or nil when the vault holds none.
    ///
    /// The documented location is checked first; failing that the root is walked for a file of the
    /// right ``filename``, taking the first by sorted relative path. The walk exists because the
    /// vault's own triage convention *moves* notes between folders — pinning the note to
    /// `reference/` would break it the first time it was filed somewhere else. Renaming the file is
    /// the one thing that does break discovery, which is why the filename is the contract.
    ///
    /// nil on a missing or unreadable file: the caller degrades to no interests, which is exactly
    /// the behaviour before this note existed (mirrors ``NewsProfileCatalog/load(configDirectory:)``).
    public static func load(knowledgeRoot: URL) -> NewsInterestNote? {
        guard let url = locate(knowledgeRoot: knowledgeRoot),
              let markdown = try? String(contentsOf: url, encoding: .utf8)
        else { return nil }
        return parse(markdown)
    }

    /// Where the note lives under the root, or nil when it is not there.
    static func locate(knowledgeRoot: URL) -> URL? {
        let preferred = knowledgeRoot.appendingPathComponent(preferredRelativePath)
        if FileManager.default.fileExists(atPath: preferred.path) { return preferred }

        guard let walker = FileManager.default.enumerator(
            at: knowledgeRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return nil }

        var found: [String] = []
        for case let url as URL in walker where url.lastPathComponent == filename {
            found.append(url.path)
        }
        return found.sorted().first.map { URL(fileURLWithPath: $0) }
    }
}
