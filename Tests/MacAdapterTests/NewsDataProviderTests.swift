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
        host: "https://newsdata.io", category: "technology", language: "en", apiToken: "SECRET_KEY"
    ))
    let url = try #require(request.url?.absoluteString)
    #expect(url.contains("/api/1/latest"))
    #expect(url.contains("category=technology"))
    #expect(url.contains("language=en"))
    // The key is in the header, and NOT anywhere in the URL.
    #expect(!url.contains("SECRET_KEY"))
    #expect(request.value(forHTTPHeaderField: "X-ACCESS-KEY") == "SECRET_KEY")
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

#endif
