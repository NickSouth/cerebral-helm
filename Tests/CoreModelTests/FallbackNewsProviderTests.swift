import Foundation
import Testing

import CerebralCore

/// The provider chain behind the News panel (the news quota fix, increment 2). The panel is backed
/// by a metered provider, so the chain's job is to keep it working through a rate limit, an outage,
/// or an unconfigured key — while still surfacing the configured provider's own diagnosis when
/// nothing at all can serve.

private struct RecordingNewsProvider: NewsProvider {
    let outcome: Result<[NewsHeadline], NewsError>
    let calls: Counter

    final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        var count: Int { lock.lock(); defer { lock.unlock() }; return value }
        func increment() { lock.lock(); value += 1; lock.unlock() }
    }

    func headlines(profile: String, apiToken: String) async throws -> [NewsHeadline] {
        calls.increment()
        return try outcome.get()
    }
}

private func provider(
    _ outcome: Result<[NewsHeadline], NewsError>
) -> (RecordingNewsProvider, RecordingNewsProvider.Counter) {
    let counter = RecordingNewsProvider.Counter()
    return (RecordingNewsProvider(outcome: outcome, calls: counter), counter)
}

private let primaryNews = [NewsHeadline(id: "p1", title: "Primary story", source: "NewsData")]
private let fallbackNews = [NewsHeadline(id: "f1", title: "Fallback story", source: "BBC News")]

@Test("the first provider that yields headlines wins; later providers are never asked")
func fallbackUsesFirstSuccess() async throws {
    let (first, firstCalls) = provider(.success(primaryNews))
    let (second, secondCalls) = provider(.success(fallbackNews))

    let headlines = try await FallbackNewsProvider([first, second]).headlines(profile: "broad", apiToken: "tok")

    #expect(headlines == primaryNews)
    #expect(firstCalls.count == 1)
    #expect(secondCalls.count == 0, "a satisfied chain must not spend the next provider's request")
}

@Test("a failing provider falls through to the next one")
func fallbackFallsThroughOnFailure() async throws {
    let (first, _) = provider(.failure(.providerFailed("rate limited")))
    let (second, secondCalls) = provider(.success(fallbackNews))

    let headlines = try await FallbackNewsProvider([first, second]).headlines(profile: "broad", apiToken: "tok")

    #expect(headlines == fallbackNews)
    #expect(secondCalls.count == 1)
}

@Test("an empty result falls through — an empty panel is not a usable answer")
func fallbackFallsThroughOnEmpty() async throws {
    let (first, _) = provider(.success([]))
    let (second, _) = provider(.success(fallbackNews))

    let headlines = try await FallbackNewsProvider([first, second]).headlines(profile: "broad", apiToken: "tok")

    #expect(headlines == fallbackNews)
}

@Test("when every provider fails the first error is rethrown, keeping the actionable diagnosis")
func fallbackRethrowsFirstError() async throws {
    let (first, _) = provider(.failure(.credentialsMissing))
    let (second, _) = provider(.failure(.providerFailed("the feed is down")))

    await #expect(throws: NewsError.credentialsMissing) {
        try await FallbackNewsProvider([first, second]).headlines(profile: "broad", apiToken: "")
    }
}

@Test("a missing key is not surfaced while a free provider can still serve")
func fallbackHidesCredentialsMissingWhenFallbackServes() async throws {
    let (metered, _) = provider(.failure(.credentialsMissing))
    let (free, _) = provider(.success(fallbackNews))

    let headlines = try await FallbackNewsProvider([metered, free]).headlines(profile: "broad", apiToken: "")

    #expect(headlines == fallbackNews)
}

@Test("an empty chain fails honestly rather than returning an empty list")
func fallbackEmptyChainThrows() async throws {
    await #expect(throws: NewsError.self) {
        try await FallbackNewsProvider([]).headlines(profile: "broad", apiToken: "tok")
    }
}

@Test("every provider is passed the same profile and token")
func fallbackForwardsProfileAndToken() async throws {
    actor Seen {
        var profiles: [String] = []
        var tokens: [String] = []
        func record(_ profile: String, _ token: String) {
            profiles.append(profile)
            tokens.append(token)
        }
    }
    struct Spy: NewsProvider {
        let seen: Seen
        func headlines(profile: String, apiToken: String) async throws -> [NewsHeadline] {
            await seen.record(profile, apiToken)
            throw NewsError.providerFailed("always fails")
        }
    }
    let seen = Seen()
    _ = try? await FallbackNewsProvider([Spy(seen: seen), Spy(seen: seen)])
        .headlines(profile: "engineering", apiToken: "tok")

    #expect(await seen.profiles == ["engineering", "engineering"])
    #expect(await seen.tokens == ["tok", "tok"])
}
