#if canImport(AppKit)
import Foundation
import CerebralCore
import CerebralTools

/// Composes the macOS capability bundle (NIC-78): honest native adapters where
/// they exist, and `.none`-matrix mocks for the slots whose native adapters have
/// not landed yet — so an invocation of those tools reports a truthful
/// `unavailable` instead of a mock success. Each adapter increment flips its slot
/// and adds its id to `nativeCapabilityIDs`, which also drives the bridge's
/// handshake capability flags (FR-SHL-06).
public enum MacToolCapabilities {
    /// The composed native capability bundle plus the concrete adapters the
    /// shell needs directly: the status actor (the publisher streams the same
    /// instance's snapshots, sharing rate-metric delta state with the one-shot
    /// tool) and the Keychain secret store (NIC-82 — carried here rather than on
    /// `ToolCapabilities` because no tool handler consumes secrets in the MVP;
    /// config resolution and the settings provisioning flow are its consumers).
    public struct Composition {
        public let capabilities: ToolCapabilities
        public let systemStatus: MacSystemStatusCapability
        public let secretStore: KeychainSecretCapability
        /// The Linear GraphQL client (quick-actions phase 4). Exposed on the composition so the
        /// bridge's read-only `listLinearOptions` closure can use the same client — and the same
        /// Keychain-resolved key — as the write tool, without going through the tool.
        public let linear: LinearAPIClient
        /// URL-quick-app favicon fetcher (NIC-147). Carried here rather than on
        /// `ToolCapabilities` because no tool handler consumes it — `BridgeSession`
        /// drives it directly off `listUrls`/`addUrlReference`, like `secretStore`.
        public let favicon: MacFaviconCapability
        /// Chrome profile enumeration for the profile dropdown + avatar badges
        /// (NIC-151). Like `favicon`, `BridgeSession` drives it directly off
        /// `listChromeProfiles` — not a gated tool.
        public let chromeProfiles: MacChromeProfileDiscoveryCapability
    }

    /// `referenceStore` is the shared, reloadable catalog (NIC-146): the app/url
    /// capabilities read their target maps through it, so a mid-session mint (reloaded
    /// via `CommandRuntime.updateReferences`) resolves without a relaunch — the same
    /// store the runtime's parser reads.
    ///
    /// `urlOpenRegistry` + `currentModeProvider` opt the URL adapter into re-open
    /// tab surfacing (NIC-145): a URL CH already opened in the active mode is
    /// surfaced through `browserTabSurface` instead of duplicated. The defaults
    /// (a throwaway registry and a `nil` mode) keep the plain open behavior, so
    /// callers and tests that only pass `referenceStore` are unaffected.
    public static func make(
        referenceStore: CommandReferenceStore,
        workspace: any WorkspaceOpening = SystemWorkspace(),
        browserTabSurface: any BrowserTabSurface = DefaultBrowserTabSurface(),
        urlOpenRegistry: SessionURLOpenRegistry = SessionURLOpenRegistry(),
        currentModeProvider: @escaping @Sendable () -> String? = { nil },
        layoutDisplay: @escaping @Sendable () -> WindowDisplay? = { nil },
        reservedStrips: @escaping @Sendable () -> [ReservedStrip] = { [] },
        spotifyRefresh: SpotifyRefreshSignal = SpotifyRefreshSignal()
    ) -> Composition {
        let systemStatus = MacSystemStatusCapability()
        let secretStore = KeychainSecretCapability()
        let favicon = MacFaviconCapability()
        let chromeProfiles = MacChromeProfileDiscoveryCapability()
        // One launcher shared by both open paths so its profile→window registry is
        // consistent across app-tile and URL-tile opens (NIC-151).
        let chromeLauncher = ChromeProfileLauncher(workspace: workspace)
        let linearClient = LinearAPIClient(secretStore: secretStore)
        return Composition(
            capabilities: ToolCapabilities(
                app: NSWorkspaceAppCapability(
                    appsProvider: { referenceStore.current.apps }, workspace: workspace,
                    chromeLauncher: chromeLauncher, currentModeProvider: currentModeProvider
                ),
                project: NSWorkspaceProjectCapability(
                    appsProvider: { referenceStore.current.apps }, workspace: workspace
                ),
                url: NSWorkspaceURLCapability(
                    urlsProvider: { referenceStore.current.urls },
                    workspace: workspace,
                    surface: browserTabSurface,
                    registry: urlOpenRegistry,
                    currentModeProvider: currentModeProvider,
                    chromeLauncher: chromeLauncher
                ),
                process: ProcessHookCapability(),
                systemStatus: systemStatus,
                networkSpeedTest: MacNetworkSpeedTestCapability(),
                workspaceWindows: MacWorkspaceWindowsCapability(),
                window: AXWindowCapability(layoutDisplay: layoutDisplay, reservedStrips: reservedStrips),
                appDiscovery: MacAppDiscoveryCapability(),
                applicationLifecycle: MacApplicationLifecycleCapability(),
                appWindows: MacAppWindowsCapability(),
                googleSearch: NSWorkspaceGoogleSearchCapability(workspace: workspace),
                youtubeSearch: NSWorkspaceYouTubeSearchCapability(workspace: workspace),
                gitClone: MacGitCloneCapability(),
                projectScaffold: ProjectScaffolder(),
                // One client serves both the write port and the workspace read; the ports stay
                // separate so a surface that only lists options cannot reach the write path.
                linearIssue: linearClient,
                webOpen: NSWorkspaceWebOpenCapability(workspace: workspace),
                calendarWrite: EventKitCalendarWriter(),
                // Playback control (NIC-133): resolves a valid token from the same Keychain-backed
                // OAuth session the now-playing publisher uses, and sends play/pause/skip to the
                // active device via the Web API.
                spotifyControl: SpotifyWebControlCapability(
                    authSession: SpotifyAuthSession(secretStore: secretStore, refresher: SpotifyTokenExchange()),
                    refreshSignal: spotifyRefresh
                ),
                // Playlist creation (quick-actions phase 4): the same Keychain-backed session,
                // a separate capability — control is transport, this writes to the library.
                spotifyPlaylist: SpotifyWebPlaylistCapability(
                    authSession: SpotifyAuthSession(secretStore: secretStore, refresher: SpotifyTokenExchange())
                ),
                nativeCapabilityIDs: [
                    CapabilityMatrix.Capability.appOpen,
                    CapabilityMatrix.Capability.projectOpen,
                    CapabilityMatrix.Capability.projectScaffold,
                    CapabilityMatrix.Capability.urlOpen,
                    CapabilityMatrix.Capability.hookRun,
                    CapabilityMatrix.Capability.systemStatusRead,
                    CapabilityMatrix.Capability.networkSpeedTest,
                    CapabilityMatrix.Capability.secret,
                    CapabilityMatrix.Capability.workspaceWindows,
                    CapabilityMatrix.Capability.window,
                    CapabilityMatrix.Capability.appsList,
                    CapabilityMatrix.Capability.googleSearch,
                    CapabilityMatrix.Capability.youtubeSearch,
                    CapabilityMatrix.Capability.gitClone,
                    CapabilityMatrix.Capability.linearIssue,
                    CapabilityMatrix.Capability.webOpen,
                    CapabilityMatrix.Capability.calendarWrite,
                    CapabilityMatrix.Capability.spotifyControl,
                    CapabilityMatrix.Capability.spotifyPlaylist,
                ]
            ),
            systemStatus: systemStatus,
            secretStore: secretStore,
            linear: linearClient,
            favicon: favicon,
            chromeProfiles: chromeProfiles
        )
    }
}
#endif
