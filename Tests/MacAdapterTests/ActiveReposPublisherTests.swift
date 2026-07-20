// NIC-131 Increment 3: streaming the active-repos widget as widget.data.changed events.
#if canImport(AppKit)
import Foundation
import Testing

import CerebralContracts
import CerebralCore
import CerebralMacAdapters

/// A scripted provider: returns a fixed repo list (or throws) so the publisher's cadence
/// and pause/resume can be exercised without touching the real filesystem.
private struct ScriptedReposProvider: ActiveReposProvider {
    let repos: [RepoStatus]
    func activeRepositories() throws -> [RepoStatus] { repos }
}

private func sampleRepos() -> [RepoStatus] {
    [
        RepoStatus(id: "cerebral-helm", name: "cerebral-helm", branch: "main",
                   path: "/p/cerebral-helm", lastActivityAt: Date(timeIntervalSince1970: 2_000)),
        RepoStatus(id: "notes", name: "notes", branch: nil,
                   path: "/p/notes", lastActivityAt: Date(timeIntervalSince1970: 1_000))
    ]
}

private final class EventCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [String] = []
    func collect(_ json: String) { lock.lock(); events.append(json); lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return events.count }
    var all: [String] { lock.lock(); defer { lock.unlock() }; return events }
}

private func waitUntil(_ deadlineMs: Int, _ condition: () -> Bool) async {
    for _ in 0..<max(1, deadlineMs / 20) {
        if condition() { return }
        try? await Task.sleep(nanoseconds: 20_000_000)
    }
}

@Test("the publisher emits widget.data.changed events for the repositories widget on cadence")
func reposPublisherEmitsOnCadence() async throws {
    let collector = EventCollector()
    let publisher = ActiveReposPublisher(
        provider: ScriptedReposProvider(repos: sampleRepos()),
        intervalMs: 50,
        emit: { collector.collect($0) }
    )
    await publisher.start()
    await waitUntil(3000) { collector.count >= 2 }
    await publisher.stop()

    #expect(collector.count >= 2)
    let event = try CerebralHelmBridgeEvent(data: Data(collector.all[0].utf8))
    #expect(event.type == .widgetDataChanged)
    #expect(event.eventID.hasPrefix("brevt_"))
    #expect(collector.all[0].contains("\"widgetId\":\"repositories\""))
    #expect(collector.all[0].contains("\"state\":\"ready\""))
    #expect(collector.all[0].contains("\"branch\":\"main\""))
}

@Test("a read failure still emits, as an honest unavailable widget")
func reposPublisherEmitsUnavailableOnFailure() async throws {
    struct FailingProvider: ActiveReposProvider {
        func activeRepositories() throws -> [RepoStatus] {
            throw ActiveReposError.rootUnavailable("/nope")
        }
    }
    let collector = EventCollector()
    let publisher = ActiveReposPublisher(
        provider: FailingProvider(), intervalMs: 50, emit: { collector.collect($0) }
    )
    await publisher.start()
    await waitUntil(3000) { collector.count >= 1 }
    await publisher.stop()

    #expect(collector.count >= 1)
    #expect(collector.all[0].contains("\"state\":\"unavailable\""))
}

@Test("a paused repos publisher emits nothing; resuming emits immediately")
func reposPublisherPauseResume() async throws {
    let collector = EventCollector()
    let publisher = ActiveReposPublisher(
        provider: ScriptedReposProvider(repos: sampleRepos()),
        intervalMs: 40,
        emit: { collector.collect($0) }
    )
    await publisher.start()
    await waitUntil(3000) { collector.count >= 1 }

    await publisher.setActive(false)
    try? await Task.sleep(nanoseconds: 60_000_000)
    let paused = collector.count
    try? await Task.sleep(nanoseconds: 250_000_000)
    #expect(collector.count == paused, "a paused publisher must not emit")

    await publisher.setActive(true)
    await waitUntil(1000) { collector.count > paused }
    #expect(collector.count > paused)
    await publisher.stop()
}
#endif
