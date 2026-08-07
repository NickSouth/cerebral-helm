// NIC-134 Increment 5: streaming the releases widget as widget.data.changed events, keyed off
// a Keychain-resolved TMDB token.
#if canImport(AppKit)
import Foundation
import Testing

import CerebralContracts
import CerebralCore
import CerebralMacAdapters
import CerebralTools

private func sampleReleases() -> [ReleaseItem] {
    [
        ReleaseItem(id: "693134", title: "Dune: Part Two", mediaType: .movie, year: 2024),
        ReleaseItem(id: "1396", title: "Breaking Bad", mediaType: .tv, year: nil),
    ]
}

private final class ReleaseEventCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [String] = []
    func collect(_ json: String) { lock.lock(); events.append(json); lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return events.count }
    var all: [String] { lock.lock(); defer { lock.unlock() }; return events }
}


@Test("with a stored key the publisher emits a ready releases widget on cadence")
func releasesPublisherEmitsReady() async throws {
    let collector = ReleaseEventCollector()
    let publisher = ReleasesPublisher(
        secretStore: MockSecretStore(values: ["tmdb_api_key": "tok"]),
        provider: MockReleaseProvider(items: sampleReleases()),
        intervalMs: 50,
        emit: { collector.collect($0) }
    )
    await publisher.start()
    await waitUntil { collector.count >= 1 }
    await publisher.stop()

    #expect(collector.count >= 1)
    let event = try CerebralHelmBridgeEvent(data: Data(collector.all[0].utf8))
    #expect(event.type == .widgetDataChanged)
    #expect(collector.all[0].contains("\"widgetId\":\"releases\""))
    #expect(collector.all[0].contains("\"state\":\"ready\""))
    #expect(collector.all[0].contains("\"title\":\"Dune: Part Two\""))
    #expect(collector.all[0].contains("\"mediaType\":\"movie\""))
    // The token is never part of the emitted event.
    #expect(!collector.all[0].contains("tok"))
}

@Test("with no stored key the publisher emits an honest add-your-key unavailable state")
func releasesPublisherEmitsCredentialsMissing() async throws {
    let collector = ReleaseEventCollector()
    let publisher = ReleasesPublisher(
        secretStore: MockSecretStore(), // empty — no key bound
        provider: MockReleaseProvider(items: sampleReleases()),
        intervalMs: 50,
        emit: { collector.collect($0) }
    )
    await publisher.start()
    await waitUntil { collector.count >= 1 }
    await publisher.stop()

    #expect(collector.count >= 1)
    #expect(collector.all[0].contains("\"state\":\"unavailable\""))
    #expect(collector.all[0].contains("TMDB API key"))
}

@Test("a provider failure emits a generic unavailable, never a fabricated list")
func releasesPublisherEmitsGenericFailure() async throws {
    let collector = ReleaseEventCollector()
    let publisher = ReleasesPublisher(
        secretStore: MockSecretStore(values: ["tmdb_api_key": "tok"]),
        provider: MockReleaseProvider(error: .providerFailed("HTTP 500")),
        intervalMs: 50,
        emit: { collector.collect($0) }
    )
    await publisher.start()
    await waitUntil { collector.count >= 1 }
    await publisher.stop()

    #expect(collector.count >= 1)
    #expect(collector.all[0].contains("\"state\":\"unavailable\""))
    #expect(!collector.all[0].contains("TMDB API key")) // not the credentials message
    #expect(!collector.all[0].contains("HTTP 500")) // raw diagnostic not leaked
}

@Test("a paused releases publisher emits nothing; resuming emits immediately")
func releasesPublisherPauseResume() async throws {
    let collector = ReleaseEventCollector()
    let publisher = ReleasesPublisher(
        secretStore: MockSecretStore(values: ["tmdb_api_key": "tok"]),
        provider: MockReleaseProvider(items: sampleReleases()),
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
#endif
