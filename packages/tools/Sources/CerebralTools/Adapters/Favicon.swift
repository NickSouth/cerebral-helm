import Foundation

// MARK: - favicon (NIC-147)

/// Fetches a site's favicon as a normalized PNG for a URL quick app (NIC-147).
///
/// A native app carries its icon inline from disk (``AppDiscoveryCapability``); a
/// URL has none, so its favicon is fetched from the site and normalized to a small
/// PNG the dashboard renders exactly like an app icon. Returns `nil` when no
/// favicon can be produced — the caller records the miss and the UI keeps its
/// placeholder glyph; this layer never invents an icon.
public protocol FaviconCapability: Sendable {
    func fetchFavicon(for url: URL) async -> Data?
}

/// A single HTTP GET, abstracted so the favicon fallback chain is testable without
/// real network. Returns the response body and its (lowercased) MIME type, or `nil`
/// on any failure — a failed fetch is a "candidate unavailable", never an error the
/// resolver has to model.
public protocol HTTPResourceFetcher: Sendable {
    func get(_ url: URL) async -> FetchedResource?
}

public struct FetchedResource: Equatable, Sendable {
    public let data: Data
    public let mimeType: String?

    public init(data: Data, mimeType: String?) {
        self.data = data
        self.mimeType = mimeType
    }
}

/// Resolves the ordered list of favicon *candidate URLs* for a web page, following
/// the chain: declared `<link rel="apple-touch-icon">` (highest resolution / color)
/// → declared `<link rel="icon">` → the well-known `/apple-touch-icon.png` and
/// `/favicon.ico` locations. It reads only the page HTML (one GET through the
/// injected fetcher); fetching and decoding the candidates themselves is the
/// platform adapter's job, so the ordering and HTML parsing here stay portable and
/// unit-testable.
public struct FaviconResolver: Sendable {
    private let fetcher: any HTTPResourceFetcher

    public init(fetcher: any HTTPResourceFetcher) {
        self.fetcher = fetcher
    }

    /// The ordered, de-duplicated candidate icon URLs to try for `url`. Reads the
    /// page HTML to honor declared icons, then appends the well-known fallbacks so
    /// a site that declares nothing still resolves. Only `http`/`https` candidates
    /// survive — a declared `href` can never redirect the fetch to another scheme.
    public func candidateURLs(for url: URL) async -> [URL] {
        var candidates: [URL] = []
        if let origin = Self.origin(of: url) {
            if let resource = await fetcher.get(origin), Self.looksLikeHTML(resource) {
                let html = String(decoding: resource.data, as: UTF8.self)
                candidates.append(contentsOf: Self.declaredIconLinks(inHTML: html, baseURL: origin))
            }
            candidates.append(contentsOf: Self.wellKnownCandidates(origin: origin))
        }
        return Self.deduplicated(candidates.filter(Self.isWebURL))
    }

    // MARK: - Origin

    /// The scheme+host[+port] root URL (`https://host/`) for a web target, or `nil`
    /// for a non-web / malformed one. Favicons are per-origin, so the page HTML is
    /// always read from the root.
    static func origin(of url: URL) -> URL? {
        guard
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let scheme = components.scheme?.lowercased(),
            scheme == "http" || scheme == "https",
            let host = components.host, !host.isEmpty
        else { return nil }
        components.scheme = scheme
        components.path = "/"
        components.query = nil
        components.fragment = nil
        components.user = nil
        components.password = nil
        return components.url
    }

    // MARK: - HTML link parsing

    private static func looksLikeHTML(_ resource: FetchedResource) -> Bool {
        guard let mime = resource.mimeType else { return true }
        return !mime.hasPrefix("image/")
    }

    private struct IconLink {
        let url: URL
        let isAppleTouch: Bool
        let size: Int
    }

    /// Declared icon links from page HTML, ordered apple-touch-icon first (they are
    /// larger and colored), then generic `icon`/`shortcut icon`, each by declared
    /// pixel size descending. Deliberately excludes `mask-icon` (a monochrome SVG).
    /// Best-effort tag scanning — a favicon is cosmetic, never worth a full HTML
    /// parser, and a missed link only falls through to the well-known locations.
    static func declaredIconLinks(inHTML html: String, baseURL: URL) -> [URL] {
        var links: [IconLink] = []
        let lower = html.lowercased()
        var searchStart = lower.startIndex
        while let tagStart = lower.range(of: "<link", range: searchStart ..< lower.endIndex) {
            let tagEnd = lower.range(of: ">", range: tagStart.upperBound ..< lower.endIndex)?.lowerBound
                ?? lower.endIndex
            // Slice the ORIGINAL (case-preserving) html so hrefs keep their case.
            let tag = String(html[tagStart.lowerBound ..< tagEnd])
            searchStart = tagEnd

            guard
                let rel = attribute("rel", in: tag)?.lowercased(),
                rel.contains("icon"), !rel.contains("mask-icon"),
                let href = attribute("href", in: tag),
                let resolved = URL(string: href, relativeTo: baseURL)?.absoluteURL
            else { continue }

            let isAppleTouch = rel.contains("apple-touch-icon")
            links.append(IconLink(url: resolved, isAppleTouch: isAppleTouch, size: parseSize(attribute("sizes", in: tag))))
        }

        return links
            .enumerated()
            .sorted { lhs, rhs in
                if lhs.element.isAppleTouch != rhs.element.isAppleTouch { return lhs.element.isAppleTouch }
                if lhs.element.size != rhs.element.size { return lhs.element.size > rhs.element.size }
                return lhs.offset < rhs.offset // stable: preserve document order on ties
            }
            .map(\.element.url)
    }

    /// The largest dimension declared in a `sizes` attribute (`"180x180"` → 180,
    /// `"16x16 32x32"` → 32); 0 when absent or `"any"`.
    private static func parseSize(_ sizes: String?) -> Int {
        guard let sizes = sizes?.lowercased() else { return 0 }
        var best = 0
        for token in sizes.split(whereSeparator: { $0 == " " || $0 == "x" }) {
            if let value = Int(token) { best = max(best, value) }
        }
        return best
    }

    /// The value of an HTML attribute within a single tag string, tolerating
    /// single/double quotes, surrounding whitespace, and any attribute order.
    static func attribute(_ name: String, in tag: String) -> String? {
        let lowerTag = tag.lowercased()
        var cursor = lowerTag.startIndex
        while let match = lowerTag.range(of: name, range: cursor ..< lowerTag.endIndex) {
            cursor = match.upperBound
            // Must be a whole attribute name: preceded by whitespace/`<`, followed by `=`.
            let before = match.lowerBound == lowerTag.startIndex
                ? " "
                : lowerTag[lowerTag.index(before: match.lowerBound)]
            guard before == " " || before == "\t" || before == "\n" || before == "<" else { continue }
            var index = match.upperBound
            while index < lowerTag.endIndex, lowerTag[index] == " " { index = lowerTag.index(after: index) }
            guard index < lowerTag.endIndex, lowerTag[index] == "=" else { continue }
            index = lowerTag.index(after: index)
            while index < lowerTag.endIndex, lowerTag[index] == " " { index = lowerTag.index(after: index) }
            guard index < lowerTag.endIndex else { return nil }

            // Read the value from the ORIGINAL tag (case preserved) at the same offset.
            let valueStart = tag.index(tag.startIndex, offsetBy: lowerTag.distance(from: lowerTag.startIndex, to: index))
            let quote = tag[valueStart]
            if quote == "\"" || quote == "'" {
                let afterQuote = tag.index(after: valueStart)
                guard let close = tag[afterQuote...].firstIndex(of: quote) else { return nil }
                return String(tag[afterQuote ..< close])
            }
            // Unquoted: read to the next whitespace or tag end.
            let end = tag[valueStart...].firstIndex { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == ">" || $0 == "/" }
                ?? tag.endIndex
            return String(tag[valueStart ..< end])
        }
        return nil
    }

    // MARK: - Well-known fallbacks

    private static func wellKnownCandidates(origin: URL) -> [URL] {
        ["apple-touch-icon.png", "apple-touch-icon-precomposed.png", "favicon.ico"]
            .compactMap { URL(string: $0, relativeTo: origin)?.absoluteURL }
    }

    // MARK: - Helpers

    private static func isWebURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    private static func deduplicated(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { seen.insert($0.absoluteString).inserted }
    }
}
