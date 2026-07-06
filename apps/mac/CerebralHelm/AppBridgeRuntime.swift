import Foundation
import CerebralBridge
import CerebralCore
import CerebralMacAdapters
import CerebralRuntimeHost
import CerebralTools
import os

/// Composes the **single** live `CommandRuntime` + `BridgeSession` for the app session
/// and routes the runtime's event stream to the dashboard (NIC-75).
///
/// Before NIC-75 the runtime was composed inside the dashboard's `WKWebViewCerebralBridge`.
/// The command palette is a second webview that must submit through the *same* bridge
/// (FR-SHL-02) without forking a second runtime over the same data root, so ownership
/// lifts here: both the dashboard transport and the palette transport are handed this
/// one `session`. Command-lifecycle and confirmation/config events flow to the dashboard
/// (where confirmations render and the mode re-themes); the palette only submits.
final class AppBridgeRuntime: @unchecked Sendable {
    let session: BridgeSession

    private let relay = EventRelay()
    /// Streams live system metrics to the dashboard (NIC-81b). Shares the status
    /// capability actor with the `system.status.read` tool.
    private let statusPublisher: SystemStatusPublisher
    /// Watches display connect/disconnect/rearrange (NIC-87). Native subscribers
    /// are told first (window re-hosting), then the dashboard via one
    /// `display.topology.changed` event.
    private let displayObserver: DisplayTopologyObserver
    /// Inputs for the runtime permission recheck (NIC-83): the composed bundle,
    /// the descriptor-declared permission requirements, and the platform checker.
    private let toolCapabilities: ToolCapabilities
    private let requiredPermissions: [String: Set<String>]
    private let permissionChecker = MacPermissionChecker()
    /// The durable settings store the session persists through — kept here so
    /// the shell can read display-hosting preferences (NIC-120b) until a
    /// settings-read bridge operation exists.
    private let settingsStore: (any SettingsStore)?
    private static let log = Logger(subsystem: "local.cerebralhelm.CerebralHelm", category: "bridge")

    /// Builds the runtime; returns nil if composition fails (the startup pre-flight has
    /// already validated config + the database, so this is not expected).
    init?(paths: WorkspacePaths) {
        // Both the lifecycle stream (from the runtime) and the confirmation/config events
        // (from the session) funnel through the relay, which forwards to the dashboard
        // sink. Capturing the relay (a reference type) rather than `self` keeps these
        // @Sendable closures free of the not-yet-initialized `session`.
        let relay = self.relay
        // The native shell composes for the macOS phase with the native capability
        // bundle (NIC-78/79): NSWorkspace app/url adapters are honest; the not-yet-
        // implemented slots (hooks, system status) truthfully report unavailable.
        guard let references = try? ReferenceCatalogLoader.load(configDirectory: paths.configDirectory) else {
            Self.log.error("Reference catalog failed to load; the shell has no live runtime.")
            return nil
        }
        let composition = MacToolCapabilities.make(references: references)
        let capabilities = composition.capabilities
        toolCapabilities = capabilities
        // Descriptors are authoritative for permission metadata (ADR-003, NIC-83):
        // a capability whose tools require a denied platform permission reports
        // unavailable with guidance instead of prompting.
        let descriptors = (try? ToolDescriptorCatalog.loadDescriptors(directory: paths.toolDescriptorsDirectory)) ?? []
        requiredPermissions = CompositionCapabilities.requiredPermissionsByCapability(descriptors)
        statusPublisher = SystemStatusPublisher(status: composition.systemStatus, emit: { relay.emit($0) })
        displayObserver = DisplayTopologyObserver(emit: { relay.emit($0) })
        guard let runtime = try? makeCommandRuntime(paths: paths, phase: .macOS, capabilities: capabilities, onEvent: { event in
            let bridgeEvent = BridgeEventFactory.lifecycleEvent(event, id: BridgeEventFactory.newEventID())
            guard let payload = try? BridgeMessageCoding.encoder().encode(bridgeEvent),
                  let json = String(data: payload, encoding: .utf8) else { return }
            relay.emit(json)
        }, onActionProgress: { progress in
            let bridgeEvent = BridgeEventFactory.workflowActionProgressEvent(
                progress, id: BridgeEventFactory.newEventID(), timestamp: Date()
            )
            guard let payload = try? BridgeMessageCoding.encoder().encode(bridgeEvent),
                  let json = String(data: payload, encoding: .utf8) else { return }
            relay.emit(json)
        }) else {
            Self.log.error("Bridge runtime composition failed; the shell has no live runtime.")
            return nil
        }
        // Settings persist in the operational database (FR-CFG-04); a store that
        // fails to open degrades to validate-only rather than losing the bridge.
        let settingsStore = try? makeSettingsStore(paths)
        if settingsStore == nil {
            Self.log.error("Settings store failed to open; settings changes will not persist.")
        }
        self.settingsStore = settingsStore
        session = BridgeSession(
            runtime: runtime,
            configDirectory: paths.configDirectory,
            capabilities: CompositionCapabilities.bridgeCapabilities(
                phase: .macOS,
                capabilities: capabilities,
                requiredPermissions: requiredPermissions,
                permissions: permissionChecker
            ),
            settingsStore: settingsStore,
            // Bootstrap restores the last active mode across restarts (FR-MOD-05).
            modeStateStore: try? makeModeStateStore(paths),
            emitEventJSON: { relay.emit($0) }
        )
    }

    /// Re-derive the capability flags from current platform permissions (NIC-83).
    /// Called when the app becomes active — the moment a user returns from System
    /// Settings after granting or revoking a permission. Each availability
    /// transition is announced with one `bridge.capability.changed` event; future
    /// handshakes report the updated set.
    func recheckPermissions() {
        let updated = CompositionCapabilities.bridgeCapabilities(
            phase: .macOS,
            capabilities: toolCapabilities,
            requiredPermissions: requiredPermissions,
            permissions: permissionChecker
        )
        for changed in session.updateCapabilities(updated) {
            let event = BridgeEventFactory.capabilityChangedEvent(
                changed, id: BridgeEventFactory.newEventID(), timestamp: Date()
            )
            guard let payload = try? BridgeMessageCoding.encoder().encode(event),
                  let json = String(data: payload, encoding: .utf8) else { continue }
            relay.emit(json)
        }
    }

    /// Route runtime/session events to the given sink — the dashboard transport. Set once
    /// the dashboard webview exists; events emitted before then have no consumer (no
    /// command has run yet, so none are emitted).
    func setEventSink(_ sink: @escaping (String) -> Void) {
        relay.setSink(sink)
    }

    /// Start the live metrics stream (call once the event sink is bound, so the
    /// first snapshot has a consumer).
    func startStatusPublishing() {
        let publisher = statusPublisher
        Task { await publisher.start() }
    }

    /// Pause/resume the metrics stream from the shell's visibility signal
    /// (dashboard occluded → no sampling; MAC-ADAPTER-3 battery AC).
    func setStatusPublishingActive(_ active: Bool) {
        let publisher = statusPublisher
        Task { await publisher.setActive(active) }
    }

    /// The persisted "Main display" id (NIC-120b) — nil when never set. A stale
    /// or disconnected id is the coordinator's problem to degrade (system primary).
    func storedMainDisplayID() -> String? {
        guard let settingsStore, let settings = try? settingsStore.load() else { return nil }
        return settings.mainDisplayID
    }

    /// Start display-topology observation (NIC-87). Main thread only — the
    /// native subscriber performs AppKit window work. The initial snapshot is
    /// published immediately so the dashboard always holds a current topology.
    func startDisplayObservation(
        onChange: @escaping (BridgeEventFactory.DisplayTopologyPayload) -> Void
    ) {
        displayObserver.onTopologyChange = onChange
        displayObserver.start()
    }
}

/// A thread-safe holder for the single event sink, shared by the runtime's event closure
/// and the session's emitter so neither captures the still-initializing `AppBridgeRuntime`.
private final class EventRelay: @unchecked Sendable {
    private let lock = NSLock()
    private var sink: ((String) -> Void)?

    func setSink(_ sink: @escaping (String) -> Void) {
        lock.lock(); self.sink = sink; lock.unlock()
    }

    func emit(_ json: String) {
        lock.lock(); let sink = self.sink; lock.unlock()
        sink?(json)
    }
}
