// Display detection and hot-plug events (NIC-87, FR-SHL-06).
#if canImport(AppKit)
import AppKit
import CoreGraphics
import Foundation
import CerebralCore
import CerebralRuntimeHost

/// Reads the current display topology. A seam so the observer's diff/emit logic
/// is unit-testable with scripted topologies — no real display hardware.
public protocol DisplayTopologyReading: Sendable {
    func currentTopology() -> BridgeEventFactory.DisplayTopologyPayload
}

/// Watches the display topology and announces real transitions (NIC-87):
/// connect, disconnect, and rearrangement all surface through AppKit's single
/// screen-parameters notification, so each notification re-reads the topology
/// and compares whole snapshots — redundant notifications emit nothing.
///
/// Two audiences per transition, in order:
/// 1. Native subscribers (`onTopologyChange`) — the window coordinator re-hosts
///    stranded shell windows *before* the dashboard is told the world changed.
/// 2. The dashboard, via one `display.topology.changed` bridge event.
///
/// Main-thread confined: `start`/`stop`/`refresh` must be called on main (the
/// screen-parameters notification already arrives there), matching the AppKit
/// window work the native subscriber performs.
public final class DisplayTopologyObserver {
    private let source: any DisplayTopologyReading
    private let emit: @Sendable (String) -> Void
    private var lastTopology: BridgeEventFactory.DisplayTopologyPayload?
    private var notificationObserver: NSObjectProtocol?

    /// Native subscriber, invoked on main before the bridge event is emitted.
    public var onTopologyChange: ((BridgeEventFactory.DisplayTopologyPayload) -> Void)?

    public init(
        source: any DisplayTopologyReading = LiveDisplayTopologySource(),
        emit: @escaping @Sendable (String) -> Void
    ) {
        self.source = source
        self.emit = emit
    }

    deinit {
        if let notificationObserver {
            NotificationCenter.default.removeObserver(notificationObserver)
        }
    }

    /// Publishes the initial snapshot (the dashboard always holds a current
    /// topology) and subscribes to screen-parameter changes. Idempotent.
    public func start() {
        guard notificationObserver == nil else { return }
        notificationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }
        refresh()
    }

    public func stop() {
        if let notificationObserver {
            NotificationCenter.default.removeObserver(notificationObserver)
        }
        notificationObserver = nil
    }

    /// Re-read the topology; on a real transition notify native subscribers and
    /// emit one bridge event. Safe to call directly (tests, manual re-check).
    public func refresh() {
        let topology = source.currentTopology()
        guard topology != lastTopology else { return }
        lastTopology = topology
        onTopologyChange?(topology)
        let event = BridgeEventFactory.displayTopologyChangedEvent(
            topology, id: BridgeEventFactory.newEventID(), timestamp: Date()
        )
        guard
            let data = try? BridgeMessageCoding.encoder().encode(event),
            let json = String(data: data, encoding: .utf8)
        else { return }
        emit(json)
    }
}

/// The live topology read: `NSScreen.screens` for logical bounds and names,
/// CoreGraphics for identity. `CGDisplayCreateUUIDFromDisplayID` provides the
/// stable cross-reconnect identity; a display the platform cannot give a UUID
/// for degrades to a session-scoped `cgid-<number>` id flagged
/// `stableIdentity: false` — consumers must not persist it (safe-degradation AC).
public struct LiveDisplayTopologySource: DisplayTopologyReading {
    public init() {}

    public func currentTopology() -> BridgeEventFactory.DisplayTopologyPayload {
        let mainDisplayID = CGMainDisplayID()
        let displays = NSScreen.screens.enumerated().map { index, screen -> BridgeEventFactory.DisplayDescriptor in
            let displayID = (screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
            ] as? NSNumber).map { CGDirectDisplayID($0.uint32Value) }
            let identity = displayID.flatMap(Self.stableIdentity(for:))
            return BridgeEventFactory.DisplayDescriptor(
                id: identity ?? "cgid-\(displayID.map(String.init) ?? "unknown-\(index)")",
                name: screen.localizedName,
                frame: WindowRect(
                    x: screen.frame.origin.x,
                    y: screen.frame.origin.y,
                    width: screen.frame.width,
                    height: screen.frame.height
                ),
                primary: displayID == mainDisplayID,
                stableIdentity: identity != nil
            )
        }
        return BridgeEventFactory.DisplayTopologyPayload(displays: displays)
    }

    private static func stableIdentity(for displayID: CGDirectDisplayID) -> String? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else {
            return nil
        }
        return CFUUIDCreateString(nil, uuid) as String
    }
}
#endif
