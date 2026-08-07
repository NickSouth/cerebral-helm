// NIC-127 Increment 7: streaming the News panel as news.changed events per relevance profile,
// keyed off a Keychain-resolved NewsData token.
#if canImport(AppKit)
import Foundation
import Testing

import CerebralContracts
import CerebralCore
import CerebralMacAdapters
import CerebralTools

private func sampleNews() -> [NewsHeadline] {
    [
        NewsHeadline(id: "n1", title: "Markets steady", source: "Reuters", url: "https://ex.com/a"),
        NewsHeadline(id: "n2", title: "Rates held", source: "Bloomberg", url: "https://ex.com/b"),
    ]
}

private final class NewsEventCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [String] = []
    func collect(_ json: String) { lock.lock(); events.append(json); lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return events.count }
    var all: [String] { lock.lock(); defer { lock.unlock() }; return events }
}


@Test("with a stored key the publisher emits one ready news.changed per profile; token never leaks")
func newsPublisherEmitsReadyPerProfile() async throws {
    let collector = NewsEventCollector()
    let publisher = NewsPublisher(
        profiles: ["broad", "engineering"],
        secretStore: MockSecretStore(values: ["newsdata_api_key": "tok"]),
        provider: MockNewsProvider(headlines: sampleNews()),
        intervalMs: 50,
        emit: { collector.collect($0) }
    )
    await publisher.start()
    await waitUntil { collector.count >= 2 }
    await publisher.stop()

    #expect(collector.count >= 2)
    let firstTwo = Array(collector.all.prefix(2)).joined(separator: "\n")
    let event = try CerebralHelmBridgeEvent(data: Data(collector.all[0].utf8))
    #expect(event.type == .newsChanged)
    #expect(firstTwo.contains("\"state\":\"ready\""))
    #expect(firstTwo.contains("\"title\":\"Markets steady\""))
    // One event per distinct profile.
    #expect(firstTwo.contains("\"profile\":\"broad\""))
    #expect(firstTwo.contains("\"profile\":\"engineering\""))
    // The token is never part of an emitted event.
    #expect(!firstTwo.contains("tok"))
}

@Test("with no stored key and nothing else able to serve, the add-your-key guidance is emitted")
func newsPublisherEmitsCredentialsMissing() async throws {
    let collector = NewsEventCollector()
    let publisher = NewsPublisher(
        profiles: ["broad"],
        secretStore: MockSecretStore(), // empty — no key bound
        // A provider that cannot serve without the key, and no fallback behind it: this is the
        // only shape in which the key prompt is the honest thing to show.
        provider: MockNewsProvider(error: .credentialsMissing),
        intervalMs: 50,
        emit: { collector.collect($0) }
    )
    await publisher.start()
    await waitUntil { collector.count >= 1 }
    await publisher.stop()

    #expect(collector.count >= 1)
    #expect(collector.all[0].contains("\"state\":\"unavailable\""))
    #expect(collector.all[0].contains("NewsData API key"))
}

@Test("a provider failure emits a generic unavailable, never a fabricated list or leaked diagnostic")
func newsPublisherEmitsGenericFailure() async throws {
    let collector = NewsEventCollector()
    let publisher = NewsPublisher(
        profiles: ["broad"],
        secretStore: MockSecretStore(values: ["newsdata_api_key": "tok"]),
        provider: MockNewsProvider(error: .providerFailed("HTTP 500 secret-tok")),
        intervalMs: 50,
        emit: { collector.collect($0) }
    )
    await publisher.start()
    await waitUntil { collector.count >= 1 }
    await publisher.stop()

    #expect(collector.count >= 1)
    #expect(collector.all[0].contains("\"state\":\"unavailable\""))
    #expect(!collector.all[0].contains("NewsData API key")) // not the credentials message
    #expect(!collector.all[0].contains("HTTP 500")) // raw diagnostic not leaked
}

@Test("a publisher with no profiles emits nothing")
func newsPublisherNoProfilesEmitsNothing() async throws {
    let collector = NewsEventCollector()
    let publisher = NewsPublisher(
        profiles: [],
        secretStore: MockSecretStore(values: ["newsdata_api_key": "tok"]),
        provider: MockNewsProvider(headlines: sampleNews()),
        intervalMs: 40,
        emit: { collector.collect($0) }
    )
    await publisher.start()
    try? await Task.sleep(nanoseconds: 200_000_000)
    await publisher.stop()
    #expect(collector.count == 0)
}

@Test("a paused news publisher emits nothing; resuming emits immediately")
func newsPublisherPauseResume() async throws {
    let collector = NewsEventCollector()
    let publisher = NewsPublisher(
        profiles: ["broad"],
        secretStore: MockSecretStore(values: ["newsdata_api_key": "tok"]),
        provider: MockNewsProvider(headlines: sampleNews()),
        intervalMs: 40,
        emit: { collector.collect($0) }
    )
    await publisher.start()
    await waitUntil { collector.count >= 1 }

    await publisher.setActive(false)
    try? await Task.sleep(nanoseconds: 60_000_000)
    let paused = collector.count
    try? await Task.sleep(nanoseconds: 250_000_000)
    #expect(collector.count == paused, "a paused publisher must not emit")

    await publisher.setActive(true)
    await waitUntil { collector.count > paused }
    #expect(collector.count > paused)
    await publisher.stop()
}

// MARK: - Quota discipline: the minimum fetch interval + the persisted last-good cache
//
// The News producer spends one provider request per profile per tick against a ~200/day free
// quota. The scheduled cadence is affordable; the out-of-cadence ticks were not — `start()` and
// every dashboard visibility resume fetched immediately, and the dashboard is a backdrop window
// whose occlusion flips whenever a full-screen app covers it. These tests pin the two rules that
// fix it: no fetch within the floor of the last *attempt*, and a cache that survives relaunch.
//
// Ticks are driven through a false→true `setActive` transition rather than the sampling loop, so
// each test triggers an exact number of non-forced ticks with no timing race.

/// Counts provider calls so a test can assert requests were *not* spent, and can be flipped to
/// failing mid-test to exercise the last-good path.
private actor CountingNewsProvider: NewsProvider {
    private var calls = 0
    private var failing: Bool
    private let items: [NewsHeadline]

    init(items: [NewsHeadline], failing: Bool = false) {
        self.items = items
        self.failing = failing
    }

    var callCount: Int { calls }

    func setFailing(_ value: Bool) { failing = value }

    func headlines(profile: String, apiToken: String) async throws -> [NewsHeadline] {
        calls += 1
        // Stands in for a metered provider, so it needs the key exactly as NewsDataProvider does.
        if apiToken.isEmpty { throw NewsError.credentialsMissing }
        if failing { throw NewsError.providerFailed("rate limited") }
        return items
    }
}

/// A hand-advanced clock: the floor and the cache-age horizon are measured in wall-clock time, so
/// the tests move time explicitly rather than sleeping. Unsynchronised on purpose — these tests
/// drive one tick at a time and `await` each to completion, so there is never a concurrent access,
/// and a lock would be unavailable from the async context the publisher reads it in.
private final class TestClock: @unchecked Sendable {
    private var current: Date

    init(_ start: Date = Date(timeIntervalSince1970: 1_750_000_000)) { current = start }

    func now() -> Date { current }

    func advance(_ seconds: TimeInterval) { current = current.addingTimeInterval(seconds) }
}

/// One non-forced tick, driven through the visibility signal the shell uses.
private func resume(_ publisher: NewsPublisher) async {
    await publisher.setActive(false)
    await publisher.setActive(true)
}

private func makeQuotaPublisher(
    profiles: [String] = ["broad"],
    provider: CountingNewsProvider,
    cacheStore: any NewsCacheStore,
    clock: TestClock,
    secretStore: any SecretStoreManaging = MockSecretStore(values: ["newsdata_api_key": "tok"]),
    minimumFetchIntervalMs: Int = 2_700_000,
    maximumCacheAgeMs: Int = 43_200_000,
    collector: NewsEventCollector
) -> NewsPublisher {
    NewsPublisher(
        profiles: profiles,
        secretStore: secretStore,
        provider: provider,
        intervalMs: 3_600_000,
        minimumFetchIntervalMs: minimumFetchIntervalMs,
        maximumCacheAgeMs: maximumCacheAgeMs,
        cacheStore: cacheStore,
        now: { clock.now() },
        emit: { collector.collect($0) }
    )
}

@Test("repeated resumes inside the floor emit from cache and spend no extra provider requests")
func newsPublisherFloorBlocksOutOfCadenceFetches() async throws {
    let collector = NewsEventCollector()
    let provider = CountingNewsProvider(items: sampleNews())
    let clock = TestClock()
    let publisher = makeQuotaPublisher(
        provider: provider, cacheStore: InMemoryNewsCacheStore(), clock: clock, collector: collector
    )

    await resume(publisher) // first tick: nothing cached, so it fetches
    #expect(await provider.callCount == 1)

    // Five occlusion flaps a few minutes apart — the shape that quietly drained the quota.
    for _ in 0..<5 {
        clock.advance(120)
        await resume(publisher)
    }

    #expect(await provider.callCount == 1, "ticks inside the floor must not spend a request")
    #expect(collector.count == 6, "every tick still emits — from cache when it does not fetch")
    #expect(collector.all.allSatisfy { $0.contains("\"state\":\"ready\"") })
    #expect(collector.all.last?.contains("Markets steady") == true)

    // Past the floor, the next tick fetches again.
    clock.advance(2_700)
    await resume(publisher)
    #expect(await provider.callCount == 2)
}

@Test("a persisted cache survives relaunch: a fresh publisher renders from disk without fetching")
func newsPublisherCacheSurvivesRelaunch() async throws {
    let store = InMemoryNewsCacheStore()
    let clock = TestClock()
    let provider = CountingNewsProvider(items: sampleNews())

    let firstRun = NewsEventCollector()
    await resume(makeQuotaPublisher(
        provider: provider, cacheStore: store, clock: clock, collector: firstRun
    ))
    #expect(await provider.callCount == 1)

    // A rebuild-and-relaunch a minute later: a brand-new publisher over the same store.
    clock.advance(60)
    let secondRun = NewsEventCollector()
    await resume(makeQuotaPublisher(
        provider: provider, cacheStore: store, clock: clock, collector: secondRun
    ))

    #expect(await provider.callCount == 1, "a relaunch inside the floor must not spend a request")
    #expect(secondRun.count == 1)
    #expect(secondRun.all[0].contains("\"state\":\"ready\""))
    #expect(secondRun.all[0].contains("Markets steady"))
}

@Test("refresh() bypasses the floor — storing a key goes live at once")
func newsPublisherRefreshBypassesFloor() async throws {
    let collector = NewsEventCollector()
    let provider = CountingNewsProvider(items: sampleNews())
    let clock = TestClock()
    let publisher = makeQuotaPublisher(
        provider: provider, cacheStore: InMemoryNewsCacheStore(), clock: clock, collector: collector
    )

    await resume(publisher)
    #expect(await provider.callCount == 1)

    clock.advance(5)
    await publisher.refresh()
    #expect(await provider.callCount == 2, "an explicit user-initiated refresh is not floor-gated")
}

@Test("the floor is measured from the last attempt, so a failing provider is not retried each tick")
func newsPublisherFloorMeasuredFromAttemptNotSuccess() async throws {
    let collector = NewsEventCollector()
    let provider = CountingNewsProvider(items: sampleNews(), failing: true)
    let clock = TestClock()
    let publisher = makeQuotaPublisher(
        provider: provider, cacheStore: InMemoryNewsCacheStore(), clock: clock, collector: collector
    )

    for _ in 0..<4 {
        clock.advance(120)
        await resume(publisher)
    }

    #expect(await provider.callCount == 1, "a rate-limited provider must not be hammered on every resume")
    #expect(collector.all.allSatisfy { $0.contains("\"state\":\"unavailable\"") })
}

@Test("a provider failure keeps serving the last good headlines rather than blanking the panel")
func newsPublisherFailureServesLastGood() async throws {
    let collector = NewsEventCollector()
    let provider = CountingNewsProvider(items: sampleNews())
    let clock = TestClock()
    let publisher = makeQuotaPublisher(
        provider: provider, cacheStore: InMemoryNewsCacheStore(), clock: clock, collector: collector
    )

    await resume(publisher)
    await provider.setFailing(true)
    clock.advance(2_700)
    await resume(publisher)

    #expect(await provider.callCount == 2)
    #expect(collector.all.last?.contains("\"state\":\"ready\"") == true)
    #expect(collector.all.last?.contains("Markets steady") == true)
}

@Test("cached headlines past the max age are retired rather than shown as if current")
func newsPublisherRetiresStaleCache() async throws {
    let collector = NewsEventCollector()
    let provider = CountingNewsProvider(items: sampleNews())
    let clock = TestClock()
    let publisher = makeQuotaPublisher(
        provider: provider, cacheStore: InMemoryNewsCacheStore(), clock: clock,
        maximumCacheAgeMs: 3_600_000, collector: collector
    )

    await resume(publisher)
    #expect(collector.all[0].contains("\"state\":\"ready\""))

    // The provider stays down well past the horizon: the headlines are now too old to pass off
    // as current, and the region carries no staleness marker, so the panel degrades honestly.
    await provider.setFailing(true)
    clock.advance(7_200)
    await resume(publisher)

    #expect(collector.all.last?.contains("\"state\":\"unavailable\"") == true)
    #expect(collector.all.last?.contains("Markets steady") == false)
    #expect(collector.all.last?.contains("NewsData API key") == false) // generic, not the key prompt
}

@Test("with no stored key a free fallback still serves the panel instead of the key prompt")
func newsPublisherServesFallbackWithoutKey() async throws {
    let collector = NewsEventCollector()
    let clock = TestClock()
    let publisher = NewsPublisher(
        profiles: ["broad"],
        secretStore: MockSecretStore(), // empty — no key bound
        // The shipped shape: a metered provider that needs the key, a free one that does not.
        provider: FallbackNewsProvider([
            MockNewsProvider(error: .credentialsMissing),
            MockNewsProvider(headlines: sampleNews()),
        ]),
        intervalMs: 3_600_000,
        cacheStore: InMemoryNewsCacheStore(),
        now: { clock.now() },
        emit: { collector.collect($0) }
    )

    await resume(publisher)

    #expect(collector.count == 1)
    #expect(collector.all[0].contains("\"state\":\"ready\""))
    #expect(collector.all[0].contains("Markets steady"))
    #expect(
        collector.all[0].contains("NewsData API key") == false,
        "an unconfigured key must not blank a panel that a free source can serve"
    )
}

@Test("the floor defaults to 90% of the cadence, so a longer cadence really does lower spend")
func newsPublisherFloorTracksCadence() async throws {
    let collector = NewsEventCollector()
    let provider = CountingNewsProvider(items: sampleNews())
    let clock = TestClock()
    // No explicit floor: it must be derived from the interval, not left at some fixed constant
    // that a 2 h cadence would sail past on every resume.
    let publisher = NewsPublisher(
        profiles: ["broad"],
        secretStore: MockSecretStore(values: ["newsdata_api_key": "tok"]),
        provider: provider,
        intervalMs: 7_200_000, // 2 h
        cacheStore: InMemoryNewsCacheStore(),
        now: { clock.now() },
        emit: { collector.collect($0) }
    )

    await resume(publisher)
    #expect(await provider.callCount == 1)

    // An hour later — well past any 45-minute constant, but inside 90% of a 2 h cadence.
    clock.advance(3_600)
    await resume(publisher)
    #expect(await provider.callCount == 1, "a resume inside the cadence must not fetch")

    clock.advance(3_000) // now past 90% of 2 h
    await resume(publisher)
    #expect(await provider.callCount == 2)
}

@Test("a rate limit reads as temporary, not broken, and never as a key problem")
func newsPublisherRateLimitIsHonest() async throws {
    let collector = NewsEventCollector()
    let clock = TestClock()
    let publisher = NewsPublisher(
        profiles: ["broad"],
        secretStore: MockSecretStore(values: ["newsdata_api_key": "tok"]),
        // Both sources down: the metered one out of credits, the free one unreachable. The
        // metered provider's diagnosis is the one that reaches the panel.
        provider: FallbackNewsProvider([
            MockNewsProvider(error: .rateLimited),
            MockNewsProvider(error: .providerFailed("the feed is unreachable")),
        ]),
        cacheStore: InMemoryNewsCacheStore(),
        now: { clock.now() },
        emit: { collector.collect($0) }
    )

    await resume(publisher)

    #expect(collector.all[0].contains("\"state\":\"unavailable\""))
    #expect(collector.all[0].contains("rate limited"))
    #expect(collector.all[0].contains("NewsData API key") == false, "not the user's fault to fix")
}

@Test("a rate limit falls through to the free source rather than reaching the panel at all")
func newsPublisherRateLimitFallsThroughToFreeSource() async throws {
    let collector = NewsEventCollector()
    let clock = TestClock()
    let publisher = NewsPublisher(
        profiles: ["broad"],
        secretStore: MockSecretStore(values: ["newsdata_api_key": "tok"]),
        provider: FallbackNewsProvider([
            MockNewsProvider(error: .rateLimited),
            MockNewsProvider(headlines: sampleNews()),
        ]),
        cacheStore: InMemoryNewsCacheStore(),
        now: { clock.now() },
        emit: { collector.collect($0) }
    )

    await resume(publisher)

    #expect(collector.all[0].contains("\"state\":\"ready\""))
    #expect(collector.all[0].contains("Markets steady"))
}

@Test("a rate limit does not discard headlines that are still good")
func newsPublisherRateLimitKeepsLastGood() async throws {
    let collector = NewsEventCollector()
    let clock = TestClock()
    let store = InMemoryNewsCacheStore()
    let secrets = MockSecretStore(values: ["newsdata_api_key": "tok"])

    await resume(NewsPublisher(
        profiles: ["broad"], secretStore: secrets,
        provider: MockNewsProvider(headlines: sampleNews()),
        cacheStore: store, now: { clock.now() }, emit: { collector.collect($0) }
    ))

    clock.advance(7_200)
    await resume(NewsPublisher(
        profiles: ["broad"], secretStore: secrets,
        provider: MockNewsProvider(error: .rateLimited),
        cacheStore: store, now: { clock.now() }, emit: { collector.collect($0) }
    ))

    #expect(collector.all.last?.contains("\"state\":\"ready\"") == true)
    #expect(collector.all.last?.contains("Markets steady") == true)
}

@Test("resend repaints from cache without spending a request — the webview-race repair")
func newsPublisherResendRepaintsFromCache() async throws {
    let store = InMemoryNewsCacheStore()
    let clock = TestClock()
    let provider = CountingNewsProvider(items: sampleNews())
    let secrets = MockSecretStore(values: ["newsdata_api_key": "tok"])

    // A previous run warmed the cache.
    await resume(makeQuotaPublisher(
        provider: provider, cacheStore: store, clock: clock, collector: NewsEventCollector()
    ))
    #expect(await provider.callCount == 1)

    // Relaunch: the first tick is served from cache, so it is instant and can be emitted before
    // the dashboard webview has registered its receiver — that event is dropped by the shell.
    // Once the page's handshake lands, resend() must repaint it.
    let afterHandshake = NewsEventCollector()
    let publisher = makeQuotaPublisher(
        provider: provider, cacheStore: store, clock: clock, collector: afterHandshake
    )
    await publisher.resend()

    #expect(afterHandshake.count == 1, "the panel is repainted")
    #expect(afterHandshake.all[0].contains("\"state\":\"ready\""))
    #expect(afterHandshake.all[0].contains("Markets steady"))
    #expect(await provider.callCount == 1, "a repaint must never cost a provider request")
}

@Test("resend on a cold cache stays silent rather than flashing an unavailable panel")
func newsPublisherResendSilentWhenNothingCached() async throws {
    let collector = NewsEventCollector()
    let publisher = makeQuotaPublisher(
        provider: CountingNewsProvider(items: sampleNews()),
        cacheStore: InMemoryNewsCacheStore(), clock: TestClock(), collector: collector
    )

    await publisher.resend()

    #expect(collector.count == 0)
}

@Test("a missing credential is never masked by cached headlines")
func newsPublisherCredentialsMissingBeatsCache() async throws {
    let store = InMemoryNewsCacheStore()
    let clock = TestClock()
    let provider = CountingNewsProvider(items: sampleNews())

    let warm = NewsEventCollector()
    await resume(makeQuotaPublisher(provider: provider, cacheStore: store, clock: clock, collector: warm))
    #expect(warm.all[0].contains("\"state\":\"ready\""))

    // The user removed the key: the guidance must win over the still-fresh cached headlines.
    clock.advance(2_700)
    let afterRemoval = NewsEventCollector()
    await resume(makeQuotaPublisher(
        provider: provider, cacheStore: store, clock: clock,
        secretStore: MockSecretStore(), collector: afterRemoval
    ))

    #expect(afterRemoval.all[0].contains("\"state\":\"unavailable\""))
    #expect(afterRemoval.all[0].contains("NewsData API key"))
    #expect(afterRemoval.all[0].contains("Markets steady") == false)
}
#endif
