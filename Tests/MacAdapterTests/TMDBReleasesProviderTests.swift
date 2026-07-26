// NIC-134 Increment 3: TMDB request building, response parsing, and person filtering.
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

@Test("a mixed trending payload parses into movie + TV releases, dropping people")
func tmdbParsesMixedReleases() throws {
    let json = Data("""
    { "page": 1, "results": [
      { "id": 693134, "media_type": "movie", "title": "Dune: Part Two", "release_date": "2024-02-27" },
      { "id": 1396, "media_type": "tv", "name": "Breaking Bad", "first_air_date": "2008-01-20" },
      { "id": 500, "media_type": "person", "name": "Some Actor" }
    ] }
    """.utf8)

    let items = try TMDBReleasesProvider.parse(json, limit: 8)
    #expect(items.count == 2) // the person is filtered out
    #expect(items[0].id == "693134")
    #expect(items[0].title == "Dune: Part Two")
    #expect(items[0].mediaType == .movie)
    #expect(items[0].year == 2024)
    #expect(items[1].title == "Breaking Bad")
    #expect(items[1].mediaType == .tv)
    #expect(items[1].year == 2008)
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

    let items = try TMDBReleasesProvider.parse(json, limit: 8)
    #expect(items.count == 2) // the whitespace-only title is dropped
    #expect(items[0].title == "Untitled Upcoming")
    #expect(items[0].year == nil) // no date at all
    #expect(items[1].title == "No Date Series")
    #expect(items[1].year == nil) // blank date, never fabricated
}

@Test("parse caps the result at the requested limit")
func tmdbHonorsLimit() throws {
    let entries = (1...20).map { #"{ "id": \#($0), "media_type": "movie", "title": "Film \#($0)" }"# }
    let json = Data("{ \"results\": [\(entries.joined(separator: ","))] }".utf8)

    let items = try TMDBReleasesProvider.parse(json, limit: 5)
    #expect(items.count == 5)
    #expect(items.first?.title == "Film 1")
    #expect(items.last?.title == "Film 5")
}

@Test("malformed JSON throws providerFailed, never a fabricated list")
func tmdbParseFailure() {
    let garbage = Data("not json".utf8)
    #expect(throws: ReleaseError.self) {
        _ = try TMDBReleasesProvider.parse(garbage, limit: 8)
    }
}
#endif
