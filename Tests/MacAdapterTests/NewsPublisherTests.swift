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

private func waitForNews(_ deadlineMs: Int, _ condition: () -> Bool) async {
    for _ in 0..<max(1, deadlineMs / 20) {
        if condition() { return }
        try? await Task.sleep(nanoseconds: 20_000_000)
    }
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
    await waitForNews(3000) { collector.count >= 2 }
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

@Test("with no stored key every profile emits an honest add-your-key unavailable state")
func newsPublisherEmitsCredentialsMissing() async throws {
    let collector = NewsEventCollector()
    let publisher = NewsPublisher(
        profiles: ["broad"],
        secretStore: MockSecretStore(), // empty — no key bound
        provider: MockNewsProvider(headlines: sampleNews()),
        intervalMs: 50,
        emit: { collector.collect($0) }
    )
    await publisher.start()
    await waitForNews(3000) { collector.count >= 1 }
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
    await waitForNews(3000) { collector.count >= 1 }
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
    await waitForNews(3000) { collector.count >= 1 }

    await publisher.setActive(false)
    try? await Task.sleep(nanoseconds: 60_000_000)
    let paused = collector.count
    try? await Task.sleep(nanoseconds: 250_000_000)
    #expect(collector.count == paused, "a paused publisher must not emit")

    await publisher.setActive(true)
    await waitForNews(1000) { collector.count > paused }
    #expect(collector.count > paused)
    await publisher.stop()
}
#endif
