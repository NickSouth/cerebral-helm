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

@Test("a workflow action progress becomes a workflow.action.progress bridge event")
func workflowProgressEventConverts() throws {
    let progress = WorkflowActionProgress(
        commandID: "cmd_000000000000000000000001",
        workflowID: "open-developer-layout",
        actionID: "open-editor",
        kind: "app.open",
        status: .running,
        index: 2,
        total: 5
    )
    let bridgeEvent = BridgeEventFactory.workflowActionProgressEvent(
        progress, id: "brevt_test00000002", timestamp: Date(timeIntervalSince1970: 1_750_000_000)
    )
    #expect(bridgeEvent.type == .workflowActionProgress)
    #expect(bridgeEvent.payload["workflowId"] != nil)
    #expect(bridgeEvent.payload["status"] != nil)

    // Round-trips through the contract Codable.
    let decoded = try CerebralHelmBridgeEvent(data: try bridgeEvent.jsonData())
    #expect(decoded.type == .workflowActionProgress)
}

@Test("a display topology snapshot becomes a display.topology.changed bridge event")
func displayTopologyEventConverts() throws {
    let topology = BridgeEventFactory.DisplayTopologyPayload(displays: [
        BridgeEventFactory.DisplayDescriptor(
            id: "37D8832A-2D66-02CA-B9F7-8F30A301B230",
            name: "Built-in Display",
            frame: WindowRect(x: 0, y: 0, width: 1512, height: 982),
            primary: true,
            stableIdentity: true
        ),
        BridgeEventFactory.DisplayDescriptor(
            id: "cgid-724554883",
            name: "External Display",
            frame: WindowRect(x: 1512, y: -200, width: 2560, height: 1440),
            primary: false,
            stableIdentity: false
        )
    ])
    #expect(topology.primaryDisplayId == "37D8832A-2D66-02CA-B9F7-8F30A301B230")

    let bridgeEvent = BridgeEventFactory.displayTopologyChangedEvent(
        topology, id: "brevt_test00000003", timestamp: Date(timeIntervalSince1970: 1_750_000_000)
    )
    #expect(bridgeEvent.type == .displayTopologyChanged)
    #expect(bridgeEvent.payload["displays"] != nil)
    #expect(bridgeEvent.payload["primaryDisplayId"] != nil)

    // Round-trips through the contract Codable.
    let decoded = try CerebralHelmBridgeEvent(data: try bridgeEvent.jsonData())
    #expect(decoded.type == .displayTopologyChanged)
}

@Test("a single-display topology with no primary flag reports no primary id")
func displayTopologyWithoutPrimary() {
    let topology = BridgeEventFactory.DisplayTopologyPayload(displays: [
        BridgeEventFactory.DisplayDescriptor(
            id: "cgid-1", name: "Display", frame: WindowRect(x: 0, y: 0, width: 100, height: 100),
            primary: false, stableIdentity: false
        )
    ])
    #expect(topology.primaryDisplayId == nil)
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
