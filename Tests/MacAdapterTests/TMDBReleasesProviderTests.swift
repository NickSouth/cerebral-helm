// NIC-134: TMDB request building, response parsing, movie/TV balancing, and poster handling.
#if canImport(AppKit)
import Foundation
import Testing

import CerebralCore
@testable import CerebralMacAdapters

@Test("the request targets TMDB's weekly trending feed with the token in the Authorization header, not the URL")
func tmdbRequestCarriesBearerToken() throws {
    let request = try #require(TMDBReleasesProvider.makeRequest(
        host: "https://api.themoviedb.org", apiToken: "secret-token-123"
    ))
    let url = try #require(request.url)
    let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    #expect(components.host == "api.themoviedb.org")
    #expect(components.path == "/3/trending/all/week")

    // The token rides the header (v4 Bearer) — never the URL, so it can't leak into logs.
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret-token-123")
    #expect(!url.absoluteString.contains("secret-token-123"))
}

@Test("a mixed trending payload parses movie + TV entries with poster paths, dropping people")
func tmdbParsesMixedReleases() throws {
    let json = Data("""
    { "page": 1, "results": [
      { "id": 693134, "media_type": "movie", "title": "Dune: Part Two", "release_date": "2024-02-27", "poster_path": "/dune.jpg" },
      { "id": 1396, "media_type": "tv", "name": "Breaking Bad", "first_air_date": "2008-01-20", "poster_path": "/bb.jpg" },
      { "id": 500, "media_type": "person", "name": "Some Actor" }
    ] }
    """.utf8)

    let items = try TMDBReleasesProvider.parse(json)
    #expect(items.count == 2) // the person is filtered out
    #expect(items[0].id == "693134")
    #expect(items[0].title == "Dune: Part Two")
    #expect(items[0].mediaType == .movie)
    #expect(items[0].year == 2024)
    #expect(items[0].posterPath == "/dune.jpg")
    #expect(items[1].mediaType == .tv)
    #expect(items[1].posterPath == "/bb.jpg")
}

@Test("an item with no usable title is skipped, and a missing/blank date yields a nil year")
func tmdbSkipsBlanksAndOmitsUnknownYear() throws {
    let json = Data("""
    { "results": [
      { "id": 1, "media_type": "movie", "title": "Untitled Upcoming" },
      { "id": 2, "media_type": "movie", "title": "   ", "release_date": "2025-01-01" },
      { "id": 3, "media_type": "tv", "name": "No Date Series", "first_air_date": "" }
    ] }
    """.utf8)

    let items = try TMDBReleasesProvider.parse(json)
    #expect(items.count == 2) // the whitespace-only title is dropped
    #expect(items[0].title == "Untitled Upcoming")
    #expect(items[0].year == nil) // no date at all
    #expect(items[0].posterPath == nil)
    #expect(items[1].title == "No Date Series")
    #expect(items[1].year == nil) // blank date, never fabricated
}

@Test("balancing interleaves movies and shows so each 2×2 page is 2 movies + 2 shows")
func tmdbBalancesMoviesAndShows() {
    func p(_ id: String, _ t: ReleaseMediaType) -> TMDBReleasesProvider.Parsed {
        TMDBReleasesProvider.Parsed(id: id, title: id, mediaType: t, year: nil, posterPath: nil)
    }
    // 6 movies, 3 shows available.
    let all = [
        p("m1", .movie), p("m2", .movie), p("m3", .movie), p("m4", .movie), p("m5", .movie), p("m6", .movie),
        p("s1", .tv), p("s2", .tv), p("s3", .tv)
    ]
    let balanced = TMDBReleasesProvider.balanced(all, perType: 4)
    // Interleaved [m, s, m, s, ...]; movies capped at 4, shows exhausted at 3.
    #expect(balanced.map(\.id) == ["m1", "s1", "m2", "s2", "m3", "s3", "m4"])
    // The first page (first 4) is exactly 2 movies + 2 shows.
    let page1 = Array(balanced.prefix(4))
    #expect(page1.filter { $0.mediaType == .movie }.count == 2)
    #expect(page1.filter { $0.mediaType == .tv }.count == 2)
}

@Test("the poster URL joins the image base and path, and is nil for a missing path")
func tmdbPosterURL() throws {
    let url = try #require(TMDBReleasesProvider.posterURL(
        base: "https://image.tmdb.org/t/p/w185", path: "/abc.jpg"
    ))
    #expect(url.absoluteString == "https://image.tmdb.org/t/p/w185/abc.jpg")
    #expect(TMDBReleasesProvider.posterURL(base: "https://image.tmdb.org/t/p/w185", path: nil) == nil)
    #expect(TMDBReleasesProvider.posterURL(base: "https://image.tmdb.org/t/p/w185", path: "") == nil)
}

@Test("poster bytes become a data URI only when they decode as a real image")
func tmdbPosterDataURI() throws {
    // A 1×1 PNG (valid image bytes) → a data:image/png URI.
    let pngBase64 =
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="
    let png = try #require(Data(base64Encoded: pngBase64))
    let uri = try #require(TMDBReleasesProvider.posterDataURI(png))
    #expect(uri.hasPrefix("data:image/png;base64,"))

    // Garbage (an HTML error page) is not vouched for — an honest nil, never a broken image.
    #expect(TMDBReleasesProvider.posterDataURI(Data("<html>nope</html>".utf8)) == nil)
    #expect(TMDBReleasesProvider.posterDataURI(Data()) == nil)
    // Over the byte cap → nil even if it would decode.
    #expect(TMDBReleasesProvider.posterDataURI(png, byteCap: 10) == nil)
}

@Test("malformed JSON throws providerFailed, never a fabricated list")
func tmdbParseFailure() {
    let garbage = Data("not json".utf8)
    #expect(throws: ReleaseError.self) {
        _ = try TMDBReleasesProvider.parse(garbage)
    }
}
#endif
