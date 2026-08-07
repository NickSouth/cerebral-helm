import Foundation
import Testing

import CerebralTools

/// NIC-147 Increment 2: the portable favicon fallback chain. `FaviconResolver`
/// reads a page's HTML through an injected fetcher and produces the ordered
/// candidate icon URLs — apple-touch-icon (largest, colored) first, then declared
/// `<link>` icons by size, then the well-known `/apple-touch-icon.png` and
/// `/favicon.ico`. No real network: a stub fetcher serves canned HTML.

private struct StubFetcher: HTTPResourceFetcher {
    var responses: [String: FetchedResource] = [:]
    func get(_ url: URL) async -> FetchedResource? { responses[url.absoluteString] }
}

private func html(_ body: String, mime: String? = "text/html") -> FetchedResource {
    FetchedResource(data: Data(body.utf8), mimeType: mime)
}

private func urlStrings(_ urls: [URL]) -> [String] { urls.map(\.absoluteString) }

@Test("apple-touch-icon ranks above generic icons; well-known fallbacks trail")
func appleTouchRanksFirst() async {
    let fetcher = StubFetcher(responses: [
        "https://example.com/": html("""
        <html><head>
          <link rel="icon" href="/favicon-32.png" sizes="32x32">
          <link rel="apple-touch-icon" href="/touch.png" sizes="180x180">
        </head></html>
        """)
    ])
    let candidates = urlStrings(await FaviconResolver(fetcher: fetcher)
        .candidateURLs(for: URL(string: "https://example.com/some/page")!))

    #expect(candidates.prefix(2) == [
        "https://example.com/touch.png",
        "https://example.com/favicon-32.png",
    ])
    // Well-known fallbacks are appended after the declared ones.
    #expect(candidates.suffix(3) == [
        "https://example.com/apple-touch-icon.png",
        "https://example.com/apple-touch-icon-precomposed.png",
        "https://example.com/favicon.ico",
    ])
}

@Test("with no reachable HTML, only the well-known candidates remain, in order")
func wellKnownOnlyWhenNoHTML() async {
    let candidates = urlStrings(await FaviconResolver(fetcher: StubFetcher())
        .candidateURLs(for: URL(string: "https://news.example.org")!))
    #expect(candidates == [
        "https://news.example.org/apple-touch-icon.png",
        "https://news.example.org/apple-touch-icon-precomposed.png",
        "https://news.example.org/favicon.ico",
    ])
}

@Test("declared icons sort by size desc within group; mask-icon is ignored")
func sizeOrderingAndMaskIconExcluded() async {
    let fetcher = StubFetcher(responses: [
        "https://acme.test/": html("""
        <link rel="apple-touch-icon" href="/a-120.png" sizes="120x120">
        <link rel="apple-touch-icon" href="/a-180.png" sizes="180x180">
        <link rel="shortcut icon" href="/legacy.ico">
        <link rel="mask-icon" href="/pinned.svg" color="#000">
        """)
    ])
    let candidates = urlStrings(await FaviconResolver(fetcher: fetcher)
        .candidateURLs(for: URL(string: "https://acme.test/")!))

    #expect(candidates.prefix(3) == [
        "https://acme.test/a-180.png",
        "https://acme.test/a-120.png",
        "https://acme.test/legacy.ico",
    ])
    #expect(!candidates.contains("https://acme.test/pinned.svg"))
}

@Test("hrefs resolve relative, root-relative, protocol-relative, and absolute")
func hrefResolution() async {
    let fetcher = StubFetcher(responses: [
        "https://example.com/": html("""
        <link rel="apple-touch-icon" href="https://cdn.example.com/t.png">
        <link rel="icon" href="//cdn.example.net/x.png">
        <link rel="icon" href="sub/rel.png">
        """)
    ])
    let candidates = urlStrings(await FaviconResolver(fetcher: fetcher)
        .candidateURLs(for: URL(string: "https://example.com/deep/page")!))

    #expect(candidates.prefix(3) == [
        "https://cdn.example.com/t.png",              // absolute, apple-touch first
        "https://cdn.example.net/x.png",              // protocol-relative inherits https
        "https://example.com/sub/rel.png",            // relative to the origin root
    ])
}

@Test("non-http(s) declared icons are filtered out")
func nonWebCandidatesFiltered() async {
    let fetcher = StubFetcher(responses: [
        "https://example.com/": html("""
        <link rel='icon' href='data:image/png;base64,AAAA'>
        <link rel="apple-touch-icon" href="/real.png">
        """)
    ])
    let candidates = urlStrings(await FaviconResolver(fetcher: fetcher)
        .candidateURLs(for: URL(string: "https://example.com/")!))

    #expect(candidates.first == "https://example.com/real.png")
    #expect(!candidates.contains { $0.hasPrefix("data:") })
}

@Test("a non-web target yields no candidates at all")
func nonWebTargetHasNoCandidates() async {
    for target in ["file:///etc/hosts", "ftp://example.com", "not a url"] {
        guard let url = URL(string: target) else { continue }
        let candidates = await FaviconResolver(fetcher: StubFetcher()).candidateURLs(for: url)
        #expect(candidates.isEmpty)
    }
}

@Test("an image response at the origin is not parsed as HTML")
func imageResponseNotParsedAsHTML() async {
    // Some servers answer "/" with an image; it must not be scanned for <link>.
    let fetcher = StubFetcher(responses: [
        "https://example.com/": FetchedResource(data: Data([0x89, 0x50]), mimeType: "image/png")
    ])
    let candidates = urlStrings(await FaviconResolver(fetcher: fetcher)
        .candidateURLs(for: URL(string: "https://example.com/")!))
    // Falls straight through to the well-known set.
    #expect(candidates == [
        "https://example.com/apple-touch-icon.png",
        "https://example.com/apple-touch-icon-precomposed.png",
        "https://example.com/favicon.ico",
    ])
}
