// NIC-127 Increment 5: parsing NewsData.io `latest` payloads into headlines, and building the
// request with the key in the X-ACCESS-KEY header (never the URL). The pure helpers are `internal`,
// hence `@testable`. Gated so Linux CI compiles this target empty. Live API smoke is manual.
#if canImport(AppKit)
import Foundation
import Testing

@testable import CerebralMacAdapters
import CerebralCore

@Test("the request sends the key in the X-ACCESS-KEY header, never the URL (FR-OBS-03)")
func newsDataRequestKeyInHeaderNotURL() throws {
    let request = try #require(NewsDataProvider.makeRequest(
        host: "https://newsdata.io", category: "technology", language: "en",
        query: nil, apiToken: "SECRET_KEY"
    ))
    let url = try #require(request.url?.absoluteString)
    #expect(url.contains("/api/1/latest"))
    #expect(url.contains("category=technology"))
    #expect(url.contains("language=en"))
    #expect(url.contains("prioritydomain=top")) // top-domain source-quality filter
    // The key is in the header, and NOT anywhere in the URL.
    #expect(!url.contains("SECRET_KEY"))
    #expect(request.value(forHTTPHeaderField: "X-ACCESS-KEY") == "SECRET_KEY")
    // No interests → no `q` at all, so a user without the note gets the request they always got.
    #expect(!url.contains("q="))
}

@Test("interest terms ride along as a q= search beside the category filter (NIC-223)")
func newsDataRequestCarriesTheInterestQuery() throws {
    let request = try #require(NewsDataProvider.makeRequest(
        host: "https://newsdata.io", category: "technology", language: "en",
        query: "\"artificial intelligence\" OR rugby", apiToken: "SECRET_KEY"
    ))
    let url = try #require(request.url?.absoluteString)
    // Verified against the live free tier: `q` combines with category and prioritydomain.
    #expect(url.contains("category=technology"))
    #expect(url.contains("prioritydomain=top"))
    let query = try #require(URLComponents(string: url)?.queryItems?.first { $0.name == "q" }?.value)
    #expect(query == "\"artificial intelligence\" OR rugby")
}

@Test("an empty query is omitted rather than sent blank")
func newsDataRequestOmitsAnEmptyQuery() throws {
    let request = try #require(NewsDataProvider.makeRequest(
        host: "https://newsdata.io", category: "technology", language: "en",
        query: "", apiToken: "SECRET_KEY"
    ))
    #expect(!(try #require(request.url?.absoluteString)).contains("q="))
}

@Test("config's interestQuery switch decides whether interests reach the provider at all")
func newsDataHonoursTheInterestQuerySwitch() {
    let on = NewsProfileCatalog(
        language: "en", defaultCategory: "top", profiles: ["broad": "top"], interestQuery: "q"
    )
    let off = NewsProfileCatalog(
        language: "en", defaultCategory: "top", profiles: ["broad": "top"], interestQuery: "off"
    )
    let unset = NewsProfileCatalog(language: "en", defaultCategory: "top", profiles: ["broad": "top"])
    #expect(on.sendsInterestQuery)
    #expect(!off.sendsInterestQuery)
    // An older config file with no switch keeps the default behaviour rather than silently
    // disabling the feature.
    #expect(unset.sendsInterestQuery)
}

@Test("a normal payload parses id/title/source/url from the NewsData fields")
func newsDataParsesHeadlines() throws {
    let json = Data("""
    {
      "status": "success",
      "results": [
        { "article_id": "a1", "title": "Markets steady", "link": "https://ex.com/a", "source_name": "Reuters", "source_id": "reuters" },
        { "article_id": "a2", "title": "Rates held", "link": "https://ex.com/b", "source_name": "Bloomberg", "source_id": "bloomberg" }
      ]
    }
    """.utf8)
    let headlines = try NewsDataProvider.parse(json)
    #expect(headlines.count == 2)
    #expect(headlines.first?.id == "a1")
    #expect(headlines.first?.title == "Markets steady")
    #expect(headlines.first?.source == "Reuters")
    #expect(headlines.first?.url == "https://ex.com/a")
}

@Test("an item without a usable title is skipped, and a missing link yields a nil url")
func newsDataSkipsBlankTitleAndOmitsMissingLink() throws {
    let json = Data("""
    {
      "status": "success",
      "results": [
        { "article_id": "a1", "title": "   ", "link": "https://ex.com/a", "source_name": "Reuters" },
        { "article_id": "a2", "title": "Has no link", "source_name": "Wire" },
        { "article_id": "a3", "source_name": "Reuters" }
      ]
    }
    """.utf8)
    let headlines = try NewsDataProvider.parse(json)
    // Blank-title (a1) and title-less (a3) are dropped; a2 survives with a nil url.
    #expect(headlines.count == 1)
    #expect(headlines.first?.title == "Has no link")
    #expect(headlines.first?.url == nil)
}

@Test("source falls back from source_name to source_id to empty")
func newsDataSourceFallback() throws {
    let json = Data("""
    {
      "status": "success",
      "results": [
        { "article_id": "a1", "title": "One", "source_id": "only_id" },
        { "article_id": "a2", "title": "Two" }
      ]
    }
    """.utf8)
    let headlines = try NewsDataProvider.parse(json)
    #expect(headlines.first?.source == "only_id")
    #expect(headlines.last?.source == "")
}

@Test("syndicated duplicate titles are dropped (case-insensitive), keeping the first")
func newsDataDedupesTitles() throws {
    let json = Data("""
    {
      "status": "success",
      "results": [
        { "article_id": "a1", "title": "Spacetime Crystal Built", "link": "https://ex.com/a", "source_name": "Reuters" },
        { "article_id": "a2", "title": "spacetime crystal built", "link": "https://ex.com/b", "source_name": "AP" },
        { "article_id": "a3", "title": "A different story", "link": "https://ex.com/c", "source_name": "Wire" }
      ]
    }
    """.utf8)
    let headlines = try NewsDataProvider.parse(json)
    #expect(headlines.count == 2)
    #expect(headlines.map(\.id) == ["a1", "a3"]) // the first of the dupes is kept
    #expect(headlines.first?.source == "Reuters")
}

@Test("a malformed payload throws providerFailed, never a fabricated list")
func newsDataMalformedThrows() {
    #expect(throws: NewsError.self) {
        _ = try NewsDataProvider.parse(Data(#"{"nope":true}"#.utf8))
    }
}

@Test("a NewsData error payload (results as an object) throws providerFailed, not an empty success")
func newsDataErrorPayloadThrows() {
    // On error NewsData returns `results` as an object, not an array — it must not decode as OK.
    let errorPayload = Data("""
    { "status": "error", "results": { "message": "Invalid API key", "code": "Unauthorized" } }
    """.utf8)
    #expect(throws: NewsError.self) {
        _ = try NewsDataProvider.parse(errorPayload)
    }
}


@Test("an exhausted quota is classified as rate-limited, not as a generic breakage")
func newsDataClassifiesRateLimit() {
    // Collapsing every non-2xx into one message made "your key ran out of credits until tomorrow"
    // indistinguishable from "the network is down" — the panel could only ever say the latter.
    #expect(NewsDataProvider.error(for: 429) == .rateLimited)
}

@Test("a rejected key is classified as a credential problem the user can act on")
func newsDataClassifiesRejectedKey() {
    #expect(NewsDataProvider.error(for: 401) == .credentialsMissing)
    #expect(NewsDataProvider.error(for: 403) == .credentialsMissing)
}

@Test("any other status stays generic, and never leaks the response body")
func newsDataClassifiesOtherStatuses() {
    #expect(NewsDataProvider.error(for: 500) == .providerFailed("The news service returned status 500."))
    #expect(NewsDataProvider.error(for: 404) == .providerFailed("The news service returned status 404."))
}

@Test("a blank token fails before the request, so the fallback gets its turn without a wasted call")
func newsDataRejectsBlankTokenWithoutRequest() async throws {
    let catalog = NewsProfileCatalog(language: "en", defaultCategory: "top", profiles: ["broad": "top"])
    // A session pointed at an unroutable host: reaching the network at all would surface as a
    // different error than credentialsMissing.
    await #expect(throws: NewsError.credentialsMissing) {
        try await NewsDataProvider(catalog: catalog, host: "https://127.0.0.1:1")
            .headlines(profile: "broad", apiToken: "   ")
    }
}
#endif
