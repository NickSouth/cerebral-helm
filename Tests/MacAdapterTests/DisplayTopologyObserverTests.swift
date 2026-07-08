// NIC-87: display detection, hot-plug transitions, and safe identity degradation.
#if canImport(AppKit)
import Foundation
import Testing

import CerebralContracts
import CerebralCore
import CerebralMacAdapters
import CerebralRuntimeHost

/// A scripted topology source: each `currentTopology()` call returns the next
/// scripted snapshot (the last one repeats), standing in for hardware changes.
private final class ScriptedTopologySource: DisplayTopologyReading, @unchecked Sendable {
    private let lock = NSLock()
    private var snapshots: [BridgeEventFactory.DisplayTopologyPayload]

    init(_ snapshots: [BridgeEventFactory.DisplayTopologyPayload]) {
        self.snapshots = snapshots
    }

    func currentTopology() -> BridgeEventFactory.DisplayTopologyPayload {
        lock.lock(); defer { lock.unlock() }
        if snapshots.count > 1 {
            return snapshots.removeFirst()
        }
        return snapshots[0]
    }
}

/// Thread-safe recorder for emitted bridge-event JSON.
private final class EmittedEvents: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [String] = []

    func append(_ json: String) {
        lock.lock(); defer { lock.unlock() }
        events.append(json)
    }

    func snapshot() -> [String] {
        lock.lock(); defer { lock.unlock() }
        return events
    }
}

private func builtIn() -> BridgeEventFactory.DisplayDescriptor {
    BridgeEventFactory.DisplayDescriptor(
        id: "uuid-built-in", name: "Built-in Display",
        frame: WindowRect(x: 0, y: 0, width: 1512, height: 982),
        primary: true, stableIdentity: true
    )
}

private func external() -> BridgeEventFactory.DisplayDescriptor {
    BridgeEventFactory.DisplayDescriptor(
        id: "uuid-external", name: "External Display",
        frame: WindowRect(x: 1512, y: -200, width: 2560, height: 1440),
        primary: false, stableIdentity: true
    )
}

@Test("the first refresh publishes the initial topology snapshot")
@MainActor
func initialSnapshotIsPublished() throws {
    let emitted = EmittedEvents()
    let source = ScriptedTopologySource([
        BridgeEventFactory.DisplayTopologyPayload(displays: [builtIn(), external()])
    ])
    let observer = DisplayTopologyObserver(source: source, emit: { emitted.append($0) })

    observer.refresh()

    let events = emitted.snapshot()
    #expect(events.count == 1)
    let decoded = try CerebralHelmBridgeEvent(data: Data(events[0].utf8))
    #expect(decoded.type == .displayTopologyChanged)
}

@Test("a redundant screen-parameters notification emits nothing")
@MainActor
func redundantRefreshEmitsNothing() {
    let emitted = EmittedEvents()
    let source = ScriptedTopologySource([
        BridgeEventFactory.DisplayTopologyPayload(displays: [builtIn()])
    ])
    let observer = DisplayTopologyObserver(source: source, emit: { emitted.append($0) })

    observer.refresh()
    observer.refresh()
    observer.refresh()

    #expect(emitted.snapshot().count == 1)
}

@Test("a disconnect notifies native subscribers before the bridge event is emitted")
@MainActor
func disconnectNotifiesNativelyFirst() {
    let emitted = EmittedEvents()
    let order = EmittedEvents()
    let source = ScriptedTopologySource([
        BridgeEventFactory.DisplayTopologyPayload(displays: [builtIn(), external()]),
        BridgeEventFactory.DisplayTopologyPayload(displays: [builtIn()])
    ])
    let observer = DisplayTopologyObserver(source: source, emit: {
        emitted.append($0)
        order.append("bridge")
    })
    var received: [BridgeEventFactory.DisplayTopologyPayload] = []
    observer.onTopologyChange = { topology in
        received.append(topology)
        order.append("native")
    }

    observer.refresh() // two displays
    observer.refresh() // external disconnected

    #expect(received.count == 2)
    #expect(received[1].displays.map(\.id) == ["uuid-built-in"])
    #expect(received[1].primaryDisplayId == "uuid-built-in")
    #expect(emitted.snapshot().count == 2)
    // The window coordinator must be able to re-host stranded windows before
    // the dashboard reacts to the new topology.
    #expect(order.snapshot() == ["native", "bridge", "native", "bridge"])
}

@Test("the live source reports unique ids and at most one primary display")
@MainActor
func liveSourceDegradesSafely() {
    let topology = LiveDisplayTopologySource().currentTopology()

    // Headless test hosts may report zero displays — that is a valid topology,
    // not a failure (unknown identity degrades safely, never crashes).
    let ids = topology.displays.map(\.id)
    #expect(Set(ids).count == ids.count)
    #expect(topology.displays.filter(\.primary).count <= 1)
    for display in topology.displays {
        #expect(!display.id.isEmpty)
        #expect(display.frame.width > 0)
        #expect(display.frame.height > 0)
    }
    if let primaryID = topology.primaryDisplayId {
        #expect(topology.displays.contains { $0.id == primaryID && $0.primary })
    }
}
#endif
