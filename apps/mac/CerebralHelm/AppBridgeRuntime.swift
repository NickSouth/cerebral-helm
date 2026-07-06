import Foundation
import CerebralBridge
import CerebralCore
import CerebralMacAdapters
import CerebralRuntimeHost
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
        let capabilities = MacToolCapabilities.make(references: references)
        guard let runtime = try? makeCommandRuntime(paths: paths, phase: .macOS, capabilities: capabilities, onEvent: { event in
            let bridgeEvent = BridgeEventFactory.lifecycleEvent(event, id: BridgeEventFactory.newEventID())
            guard let payload = try? BridgeMessageCoding.encoder().encode(bridgeEvent),
                  let json = String(data: payload, encoding: .utf8) else { return }
            relay.emit(json)
        }) else {
            Self.log.error("Bridge runtime composition failed; the shell has no live runtime.")
            return nil
        }
        session = BridgeSession(
            runtime: runtime,
            configDirectory: paths.configDirectory,
            capabilities: CompositionCapabilities.bridgeCapabilities(phase: .macOS, capabilities: capabilities),
            emitEventJSON: { relay.emit($0) }
        )
    }

    /// Route runtime/session events to the given sink — the dashboard transport. Set once
    /// the dashboard webview exists; events emitted before then have no consumer (no
    /// command has run yet, so none are emitted).
    func setEventSink(_ sink: @escaping (String) -> Void) {
        relay.setSink(sink)
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
