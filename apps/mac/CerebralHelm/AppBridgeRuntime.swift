import Foundation
import AppKit
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
    /// Resolves the "Layout display" setting to a `WindowDisplay` for the layout
    /// arrange (NIC-142). Populated with the settings reader + live topology during
    /// init/observation; read at arrange time.
    private let layoutDisplayContext = LayoutDisplayContext()
    /// The reserved bottom-bar strips (NIC-142), pushed by the coordinator and read by
    /// the layout arrange so windows land above the bar. Thread-safe: the coordinator
    /// writes on main, the arrange reads off-main.
    private let reservedStripsBox = ReservedStripsBox()
    /// Streams live system metrics to the dashboard (NIC-81b). Shares the status
    /// capability actor with the `system.status.read` tool.
    private let statusPublisher: SystemStatusPublisher
    /// Watches display connect/disconnect/rearrange (NIC-87). Native subscribers
    /// are told first (window re-hosting), then the dashboard via one
    /// `display.topology.changed` event.
    private let displayObserver: DisplayTopologyObserver
    /// Watches the Applications folders (NIC-150): when an app is installed
    /// mid-session it re-discovers, re-mints its reference, and live-reloads the
    /// runtime's reference catalog, so `open <id>` resolves without a relaunch and
    /// without the user first opening the More Apps picker.
    private let appsFolderObserver: ApplicationsFolderObserver
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
        // Auto-mint app references (NIC-119, owner decision): every installed
        // application without a configured reference gets one minted into the
        // user catalog under the state root BEFORE the runtime composes, so all
        // apps are pinnable and `open <id>`-able from this launch. Icons are
        // skipped — this is the fast enumeration.
        if let shipped = try? ReferenceCatalogLoader.load(configDirectory: paths.configDirectory) {
            let installed = MacAppDiscoveryCapability.enumerate(includeIcons: false).apps.map {
                UserAppReferences.DiscoveredApp(bundleID: $0.bundleID, name: $0.name)
            }
            UserAppReferences.mint(
                discovered: installed,
                shipped: Array(shipped.apps.values),
                stateRoot: paths.stateRoot
            )
        }
        guard let references = try? ReferenceCatalogLoader.load(
            configDirectory: paths.configDirectory, stateRoot: paths.stateRoot
        ) else {
            Self.log.error("Reference catalog failed to load; the shell has no live runtime.")
            return nil
        }
        // One shared, reloadable catalog store (NIC-146): both the capability target
        // maps below and the runtime's parser read through it, so `addUrlReference`'s
        // reload makes a URL added mid-session openable this launch — no relaunch.
        let referenceStore = CommandReferenceStore(references)
        // The durable active-mode store is shared: `mode.apply` persists through it,
        // and the URL adapter reads the current mode through it to scope re-open tab
        // surfacing (NIC-145). One in-memory registry tracks the `(mode, url)` pairs
        // CH opened this session.
        let modeStateStore = try? makeModeStateStore(paths)
        let urlOpenRegistry = SessionURLOpenRegistry()
        // The layout arrange targets the "Layout display" setting (NIC-142). The
        // context is populated with the settings reader + live topology below/after
        // init, and read at arrange time (a much later async call).
        let layoutDisplayContext = self.layoutDisplayContext
        let reservedStripsBox = self.reservedStripsBox
        let composition = MacToolCapabilities.make(
            referenceStore: referenceStore,
            urlOpenRegistry: urlOpenRegistry,
            currentModeProvider: { modeStateStore.flatMap { try? $0.loadActiveModeID() } },
            layoutDisplay: { layoutDisplayContext.resolve() },
            reservedStrips: { reservedStripsBox.current() }
        )
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
        }, referenceStore: referenceStore) else {
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
        // Feed the layout-display resolver its persisted ids (captured directly, not
        // through `self`, so no not-yet-initialized capture) — the layout arrange
        // reads it live at open time (NIC-142).
        layoutDisplayContext.settingsReader = {
            let stored = try? settingsStore?.load()
            return (layout: stored?.layoutDisplayID, main: stored?.mainDisplayID)
        }
        session = BridgeSession(
            runtime: runtime,
            configDirectory: paths.configDirectory,
            // The full workspace enables the user-overrides layer: bootstrap
            // composes pinned quick apps in, and updateQuickApps writes through
            // the validated override path (NIC-119c).
            workspace: paths,
            capabilities: CompositionCapabilities.bridgeCapabilities(
                phase: .macOS,
                capabilities: capabilities,
                requiredPermissions: requiredPermissions,
                permissions: permissionChecker
            ),
            settingsStore: settingsStore,
            // Bootstrap restores the last active mode across restarts (FR-MOD-05).
            // The same store the URL adapter reads for surfacing scope (NIC-145).
            modeStateStore: modeStateStore,
            // Fetches + caches URL-quick-app favicons off listUrls/addUrlReference
            // (NIC-147); landed icons upgrade tiles live via mode.quickapps.changed.
            faviconCapability: composition.favicon,
            // Enumerates Chrome profiles for the profile dropdown + avatar badges
            // (NIC-151), driven off listChromeProfiles.
            chromeProfiles: composition.chromeProfiles,
            // Hides a layout's app windows on closeLayout (NIC-142) — the same
            // permission-free primitive "Windows Stored by Mode" uses.
            workspaceWindows: composition.capabilities.workspaceWindows,
            // Surfaces a quick-toggle target on toggleLayout (NIC-142). The URL
            // capability is the shared instance, so toggling to a URL reuses the
            // runtime's tab-surfacing registry (NIC-145).
            app: composition.capabilities.app,
            url: composition.capabilities.url,
            // Reads visible windows' frames for live layout capture (NIC-142).
            window: composition.capabilities.window,
            // The window navigator's per-window enumeration + actions (NIC-143):
            // list/minimize/surface/close through Accessibility.
            appWindows: composition.capabilities.appWindows,
            // Arranges a layout URL window that opens in the default browser (a
            // profiled URL always targets Chrome) — resolved live so it tracks the
            // user's default-browser choice (NIC-142).
            defaultBrowserBundleID: { Self.resolveDefaultBrowserBundleID() },
            emitEventJSON: { relay.emit($0) }
        )
        // Live app-install detection (NIC-150): the same re-mint + reference-reload
        // the shell runs at startup and `listApps` runs on picker open, driven now
        // by a debounced watch on the Applications folders — so a freshly installed
        // app is openable by id this session with no user action. Runs off-main on
        // the watcher's queue; `updateReferences` is lock-guarded.
        let referencesReload: @Sendable () -> Void = {
            guard let shipped = try? ReferenceCatalogLoader.load(configDirectory: paths.configDirectory) else { return }
            let installed = MacAppDiscoveryCapability.enumerate(includeIcons: false).apps.map {
                UserAppReferences.DiscoveredApp(bundleID: $0.bundleID, name: $0.name)
            }
            UserAppReferences.mint(
                discovered: installed, shipped: Array(shipped.apps.values), stateRoot: paths.stateRoot
            )
            guard let fresh = try? ReferenceCatalogLoader.load(
                configDirectory: paths.configDirectory, stateRoot: paths.stateRoot
            ) else { return }
            runtime.updateReferences(fresh)
        }
        appsFolderObserver = ApplicationsFolderObserver(reload: referencesReload)
        appsFolderObserver.start()
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
        let context = layoutDisplayContext
        displayObserver.onTopologyChange = { topology in
            // Keep the layout-display resolver's view of the topology current so the
            // next layout open targets the right screen (NIC-142).
            context.setDisplays(topology.displays.map {
                LayoutDisplayResolver.Display(id: $0.id, primary: $0.primary, stableIdentity: $0.stableIdentity)
            })
            onChange(topology)
        }
        displayObserver.start()
    }

    /// The persisted "Layout display" id (NIC-142) — nil when never set. Resolution +
    /// degradation is the coordinator's / resolver's job (mirrors `storedMainDisplayID`).
    func storedLayoutDisplayID() -> String? {
        guard let settingsStore, let settings = try? settingsStore.load() else { return nil }
        return settings.layoutDisplayID
    }

    /// Push the current reserved bottom-bar strips (NIC-142) so the layout arrange keeps
    /// windows above the bar. Wired by `AppDelegate` to the coordinator's strip changes.
    func setReservedStrips(_ strips: [ReservedStrip]) {
        reservedStripsBox.set(strips)
    }

    /// The bundle id of the user's default web browser (NIC-142), so a layout URL that
    /// opens there can be arranged like an app. nil when it can't be resolved.
    private static func resolveDefaultBrowserBundleID() -> String? {
        guard
            let probe = URL(string: "https://example.com"),
            let appURL = NSWorkspace.shared.urlForApplication(toOpen: probe)
        else { return nil }
        return Bundle(url: appURL)?.bundleIdentifier
    }
}

/// Thread-safe holder for the reserved bottom-bar strips (NIC-142): the coordinator
/// writes on main, the layout arrange reads off-main.
private final class ReservedStripsBox: @unchecked Sendable {
    private let lock = NSLock()
    private var strips: [ReservedStrip] = []
    func set(_ strips: [ReservedStrip]) { lock.lock(); self.strips = strips; lock.unlock() }
    func current() -> [ReservedStrip] { lock.lock(); defer { lock.unlock() }; return strips }
}

/// Thread-safe holder that resolves the "Layout display" setting to a `WindowDisplay`
/// for the layout arrange (NIC-142): the live topology plus a reader of the persisted
/// layout/main display ids, combined through `LayoutDisplayResolver`.
private final class LayoutDisplayContext: @unchecked Sendable {
    private let lock = NSLock()
    private var displays: [LayoutDisplayResolver.Display] = []
    /// Reads the persisted (layoutDisplayId, mainDisplayId); set once the store opens.
    var settingsReader: (@Sendable () -> (layout: String?, main: String?))?

    func setDisplays(_ displays: [LayoutDisplayResolver.Display]) {
        lock.lock(); self.displays = displays; lock.unlock()
    }

    /// The display a layout arrange should target, or nil when no reader is wired yet
    /// (arrange then keeps its baked display).
    func resolve() -> WindowDisplay? {
        guard let ids = settingsReader?() else { return nil }
        lock.lock(); let displays = self.displays; lock.unlock()
        return LayoutDisplayResolver.resolve(
            layoutDisplayID: ids.layout, mainDisplayID: ids.main, displays: displays
        )
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
