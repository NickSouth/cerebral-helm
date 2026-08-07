import Foundation
import Testing

import CerebralCore

/// NIC-134 Increment 2: the portable release-provider contract — a provider-neutral
/// ``ReleaseItem`` + ``ReleaseProvider`` port with a fixed-outcome mock. The real TMDB fetch
/// lands in the Mac adapter (Increment 3).

@Test("the mock provider yields its constructed items, ignoring the token")
func releaseMockYieldsItems() async throws {
    let provider = MockReleaseProvider(items: [
        ReleaseItem(id: "1", title: "Dune: Part Two", mediaType: .movie, year: 2024),
        ReleaseItem(id: "2", title: "The Bear", mediaType: .tv, year: nil),
    ])

    let items = try await provider.trending(apiToken: "ignored")
    #expect(items.count == 2)
    #expect(items.first?.title == "Dune: Part Two")
    #expect(items.first?.mediaType == .movie)
    // A missing year is preserved as nil, never fabricated.
    #expect(items.last?.year == nil)
}

@Test("the mock provider throws its constructed error")
func releaseMockThrowsError() async {
    let provider = MockReleaseProvider(error: .credentialsMissing)
    await #expect(throws: ReleaseError.credentialsMissing) {
        try await provider.trending(apiToken: "")
    }
}

@Test("ReleaseError distinguishes a missing credential from a provider failure")
func releaseErrorCasesAreDistinct() {
    #expect(ReleaseError.credentialsMissing != ReleaseError.providerFailed("boom"))
    #expect(ReleaseError.providerFailed("a") == ReleaseError.providerFailed("a"))
}

@Test("ReleaseMediaType raw values match the dashboard's mediaType strings")
func releaseMediaTypeRawValues() {
    #expect(ReleaseMediaType.movie.rawValue == "movie")
    #expect(ReleaseMediaType.tv.rawValue == "tv")
}
