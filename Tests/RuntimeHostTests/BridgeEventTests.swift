import Foundation
import Testing

import CerebralContracts
import CerebralCore
import CerebralRuntimeHost

/// NIC-74b: the runtime event stream is forwarded to the dashboard as bridge events.

private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

@Test("a lifecycle event becomes a command.lifecycle.transition bridge event")
func lifecycleEventConverts() throws {
    let url = repositoryRoot()
        .appendingPathComponent("packages/contracts/fixtures/valid/lifecycle/running-to-succeeded-event.json")
    let event = try CommandLifecycleEvent(fromURL: url)

    let bridgeEvent = BridgeEventFactory.lifecycleEvent(event, id: "brevt_test00000001")
    #expect(bridgeEvent.type == .commandLifecycleTransition)
    #expect(bridgeEvent.eventID == "brevt_test00000001")
    #expect(bridgeEvent.timestamp == event.timestamp)
    #expect(bridgeEvent.payload["commandId"] != nil)

    // Round-trips through the contract Codable (ISO-8601 timestamp is preserved).
    let decoded = try CerebralHelmBridgeEvent(data: try bridgeEvent.jsonData())
    #expect(decoded.type == .commandLifecycleTransition)
    #expect(decoded.timestamp == event.timestamp)
}

@Test("newEventID matches the contract id pattern")
func newEventIDPattern() {
    let id = BridgeEventFactory.newEventID()
    #expect(id.hasPrefix("brevt_"))
    #expect(id.count >= 14 && id.count <= 70)
}

@Test("the runtime forwards lifecycle events to onEvent while executing a command")
func runtimeForwardsEvents() async throws {
    let paths = try WorkspacePaths.temporary(repositoryRoot: repositoryRoot())
    let collector = EventCollector()
    let runtime = try makeCommandRuntime(paths: paths, onEvent: { collector.append($0) })

    _ = await runtime.submit("mode developer", source: .dashboard)

    let events = collector.snapshot()
    #expect(!events.isEmpty)
    // Each forwarded event converts to a lifecycle-transition bridge event.
    let bridgeEvents = events.map { BridgeEventFactory.lifecycleEvent($0, id: BridgeEventFactory.newEventID()) }
    #expect(bridgeEvents.allSatisfy { $0.type == .commandLifecycleTransition })
}

/// Thread-safe sink target: the runtime may invoke `onEvent` off the calling task.
private final class EventCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [CommandLifecycleEvent] = []

    func append(_ event: CommandLifecycleEvent) {
        lock.lock(); defer { lock.unlock() }
        events.append(event)
    }

    func snapshot() -> [CommandLifecycleEvent] {
        lock.lock(); defer { lock.unlock() }
        return events
    }
}
