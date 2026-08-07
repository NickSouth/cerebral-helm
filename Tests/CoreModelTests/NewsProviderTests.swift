import Foundation
import Testing

import CerebralCore

/// NIC-127 Increment 2: the portable news-provider contract — a provider-neutral
/// ``NewsHeadline`` + profile/credential-driven ``NewsProvider`` port with a fixed-outcome mock.
/// The real NewsData.io fetch lands in the Mac adapter (Increment 5).

@Test("the mock provider yields its constructed headlines, ignoring profile and token")
func newsMockYieldsHeadlines() async throws {
    let provider = MockNewsProvider(headlines: [
        NewsHeadline(id: "1", title: "Markets steady", source: "Reuters", url: "https://example.com/a"),
        NewsHeadline(id: "2", title: "Rates held", source: "Bloomberg"),
    ])

    let headlines = try await provider.headlines(profile: "broad", apiToken: "ignored")
    #expect(headlines.count == 2)
    #expect(headlines.first?.title == "Markets steady")
    #expect(headlines.first?.url == "https://example.com/a")
    // A missing url is preserved as nil, never fabricated.
    #expect(headlines.last?.url == nil)
}

@Test("the mock provider throws its constructed error")
func newsMockThrowsError() async {
    let provider = MockNewsProvider(error: .credentialsMissing)
    await #expect(throws: NewsError.credentialsMissing) {
        try await provider.headlines(profile: "broad", apiToken: "")
    }
}

@Test("NewsError distinguishes a missing credential from a provider failure")
func newsErrorCasesAreDistinct() {
    #expect(NewsError.credentialsMissing != NewsError.providerFailed("boom"))
    #expect(NewsError.providerFailed("a") == NewsError.providerFailed("a"))
}
