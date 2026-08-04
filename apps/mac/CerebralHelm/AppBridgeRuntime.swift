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
    /// Streams the live `repositories` widget to the dashboard (NIC-131) — reads active
    /// git repos under `~/Projects` and their branches. Runs on the same visibility
    /// gate as the metrics stream.
    private let reposPublisher: ActiveReposPublisher
    /// Streams the live `projects` widget to the dashboard (NIC-129) — reads the project
    /// folders under `~/Projects` and their `PROJECT.md` importance. Runs on the same
    /// visibility gate as the metrics and repos streams.
    private let projectsPublisher: ActiveProjectsPublisher
    /// Streams the bottom bar's ambient weather (NIC-169) — resolves the device location via
    /// CoreLocation (prompting at point of use) and fetches current conditions from Open-Meteo
    /// on a slow cadence. Runs on the same visibility gate as the other streams.
    private let weatherPublisher: WeatherPublisher
    /// Streams the Entertainment `releases` widget (NIC-134) — resolves the TMDB API key from
    /// the Keychain and fetches trending movies + TV on a slow cadence. Runs on the same
    /// visibility gate as the other streams; a missing key emits an honest "add your key" state.
    private let releasesPublisher: ReleasesPublisher
    /// Streams the Executive `stocks` widget (NIC-128) — resolves the user's tracked tickers from
    /// the settings store and the Finnhub API key from the Keychain, fetching a quote per symbol on
    /// a slow cadence. Same visibility gate as the other streams; an empty ticker list or a missing
    /// key emits an honest state rather than a fabricated quote.
    private let stocksPublisher: StocksPublisher
    /// Streams the bottom-left `news` panel (NIC-127) — resolves the NewsData API key from the
    /// Keychain and fetches headlines per relevance profile on a slow cadence, emitting one
    /// `news.changed` per profile. Same visibility gate as the other streams; a missing key emits
    /// an honest "add your key" state. Absent when the news config failed to load (no profiles).
    private let newsPublisher: NewsPublisher?
    private let calendarPublisher: CalendarPublisher?
    /// Retained so it keeps observing EventKit's store-changed notification for the lifetime of the
    /// runtime (NIC-126); dropping it would stop live calendar refreshes.
    private let calendarChangeObserver: CalendarChangeObserver?
    /// Streams the Developer `project-git-status` widget (NIC-130) — enumerates the local repos,
    /// reads each one's branch/sync from `.git` and GitHub remote from `origin`, and fetches the
    /// read-only GitHub report (PRs, Actions CI, commits) using the Keychain-resolved token. Same
    /// visibility gate as the other streams; local branch/sync always render while the GitHub half
    /// degrades honestly when there's no remote, no token, or a fetch failure.
    private let projectGitStatusPublisher: ProjectGitStatusPublisher
    /// Streams the Entertainment `spotify` widget (NIC-133) — resolves a valid access token from the
    /// Keychain-backed OAuth session (refreshing as needed) and reads the currently-playing track on
    /// a fast cadence. Same visibility gate as the other streams; not-connected/nothing-playing
    /// degrade honestly. Refreshed immediately after a successful connect.
    private let spotifyPublisher: SpotifyPublisher
    /// Streams the School `courses`/`deadlines` widgets (NIC-132) from the local Canvas scrape store,
    /// and the loopback endpoint the Chrome extension POSTs scrapes to. Both are absent when the store
    /// can't open — the widgets then stay at their honest bootstrap/unavailable state.
    private let canvasPublisher: CanvasWidgetPublisher?
    private let canvasIngestServer: CanvasIngestServer?
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
        // Shared hook: after a playback control succeeds, the control capability fires this and the
        // Spotify producer re-polls at once (wired below, once the publisher exists) — so a widget
        // skip/play/pause updates the track/art near-instantly, not on the next cadence tick (NIC-133).
        let spotifyRefreshSignal = SpotifyRefreshSignal()
        let composition = MacToolCapabilities.make(
            referenceStore: referenceStore,
            urlOpenRegistry: urlOpenRegistry,
            currentModeProvider: { modeStateStore.flatMap { try? $0.loadActiveModeID() } },
            layoutDisplay: { layoutDisplayContext.resolve() },
            reservedStrips: { reservedStripsBox.current() },
            spotifyRefresh: spotifyRefreshSignal
        )
        let capabilities = composition.capabilities
        toolCapabilities = capabilities
        // Descriptors are authoritative for permission metadata (ADR-003, NIC-83):
        // a capability whose tools require a denied platform permission reports
        // unavailable with guidance instead of prompting.
        let descriptors = (try? ToolDescriptorCatalog.loadDescriptors(directory: paths.toolDescriptorsDirectory)) ?? []
        requiredPermissions = CompositionCapabilities.requiredPermissionsByCapability(descriptors)
        statusPublisher = SystemStatusPublisher(status: composition.systemStatus, emit: { relay.emit($0) })
        // The active-repos widget producer (NIC-131): default provider scans ~/Projects.
        let repos = ActiveReposPublisher(emit: { relay.emit($0) })
        reposPublisher = repos
        // The active-projects widget producer (NIC-129): default provider scans ~/Projects.
        let projects = ActiveProjectsPublisher(emit: { relay.emit($0) })
        projectsPublisher = projects
        // The weather producer (NIC-169): CoreLocationProvider is @MainActor; this init runs on
        // the main thread (AppDelegate.applicationDidFinishLaunching), so assumeIsolated is safe.
        weatherPublisher = MainActor.assumeIsolated {
            WeatherPublisher(
                location: CoreLocationProvider(),
                weather: OpenMeteoWeatherProvider(),
                emit: { relay.emit($0) }
            )
        }
        // The Releases producer (NIC-134): reads the TMDB key from the Keychain (the same
        // KeychainSecretCapability the storeSecret op writes) and fetches trending releases.
        let releases = ReleasesPublisher(
            secretStore: composition.secretStore,
            provider: TMDBReleasesProvider(),
            emit: { relay.emit($0) }
        )
        releasesPublisher = releases
        // The Project Git Status producer (NIC-130): enumerates local repos under ~/Projects,
        // resolves each one's branch/sync + GitHub remote directly from `.git`, and fetches the
        // read-only GitHub report with the Keychain-resolved token (the same KeychainSecretCapability
        // the storeSecret op writes). Local branch/sync render even without a token.
        let projectGitStatus = ProjectGitStatusPublisher(
            secretStore: composition.secretStore,
            github: GitHubAPIStatusProvider(),
            emit: { relay.emit($0) }
        )
        projectGitStatusPublisher = projectGitStatus
        // The Spotify producer (NIC-133): resolves a valid access token from the Keychain-backed
        // OAuth session (refreshing as needed) and reads the currently-playing track on a fast
        // cadence. Not connected → an honest "connect" state; nothing playing → a healthy empty.
        let spotify = SpotifyPublisher(
            session: SpotifyAuthSession(
                secretStore: composition.secretStore,
                refresher: SpotifyTokenExchange()
            ),
            provider: SpotifyWebPlaybackProvider(),
            emit: { relay.emit($0) }
        )
        spotifyPublisher = spotify
        // Now that the publisher exists, point the control-refresh hook at it: a successful
        // play/pause/skip re-polls now-playing at once (NIC-133).
        spotifyRefreshSignal.setAction { Task { await spotify.refresh() } }
        // The News producer (NIC-127): reads the NewsData key from the Keychain and fetches
        // headlines per relevance profile declared in config/news/profiles.json. The profile →
        // category mapping lives in that config (not hardcoded); when it can't be loaded there are
        // no profiles to stream and the panel stays at its honest bootstrap "unavailable" state.
        // The cache store makes the last headlines survive relaunch, so a cold start renders from
        // disk instead of spending one of the provider's ~200 daily requests; a store that can't be
        // opened simply means the publisher caches in memory only (one extra request per launch).
        if let newsCatalog = NewsProfileCatalog.load(configDirectory: paths.configDirectory),
           !newsCatalog.profiles.isEmpty {
            let news = NewsPublisher(
                profiles: newsCatalog.profiles.keys.sorted(),
                secretStore: composition.secretStore,
                // Metered first, free second: NewsData when its key and quota allow, otherwise the
                // publishers' own RSS/Atom feeds — so a rate limit, an outage, or an unconfigured
                // key degrades the panel's *source*, never the panel itself.
                provider: FallbackNewsProvider([
                    NewsDataProvider(catalog: newsCatalog),
                    RSSNewsProvider(catalog: newsCatalog),
                ]),
                cacheStore: try? makeNewsCacheStore(paths),
                emit: { relay.emit($0) }
            )
            newsPublisher = news
        } else {
            newsPublisher = nil
        }
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
        // The Stocks producer (NIC-128): reads the tracked tickers from the settings store and the
        // Finnhub key from the Keychain each tick, so a Settings edit applies on the next sample.
        // Resolving through `EffectiveSettings` means an unset list falls back to the starter list
        // while an explicitly cleared list stays empty.
        let stocks = StocksPublisher(
            tickers: {
                let stored = (try? settingsStore?.load()).flatMap { $0 } ?? StoredSettings()
                return EffectiveSettings.resolveStockTickers(stored: stored)
            },
            secretStore: composition.secretStore,
            provider: FinnhubStockProvider(),
            // Best-effort, keyless ~1-month daily closes for the tile sparkline (NIC-128); a
            // failure just omits the line — the Finnhub price/change are unaffected.
            history: YahooStockHistoryProvider(),
            emit: { relay.emit($0) }
        )
        stocksPublisher = stocks
        // The Schedule producer (NIC-126): reads the day's events from EventKit and the user's
        // calendar→mode map from the settings store each tick, resolves each event to a mode (a
        // `#[mode]` tag → the mapped calendar → the default mode), and emits one schedule.changed
        // per relevance profile. The profile config (config/calendar/profiles.json) is not
        // hardcoded; when it can't be loaded there are no profiles to stream and the Today panel
        // stays at its honest bootstrap state.
        let calendar: CalendarPublisher?
        if let calendarCatalog = CalendarProfileCatalog.load(configDirectory: paths.configDirectory),
           !calendarCatalog.distinctProfiles.isEmpty {
            calendar = CalendarPublisher(
                catalog: calendarCatalog,
                calendarModeMap: {
                    let stored = (try? settingsStore?.load()).flatMap { $0 } ?? StoredSettings()
                    return EffectiveSettings.resolveCalendarModeMap(stored: stored)
                },
                provider: EventKitCalendarProvider(),
                emit: { relay.emit($0) }
            )
        } else {
            calendar = nil
        }
        calendarPublisher = calendar
        // Refresh the schedule the moment the calendar store changes (an event created/edited in
        // Calendar.app, or synced in from Google/iCloud) so it doesn't wait out the poll cadence
        // (NIC-126). Only wired when there's a producer to refresh.
        if let calendar {
            calendarChangeObserver = CalendarChangeObserver(onChange: { Task { await calendar.refresh() } })
        } else {
            calendarChangeObserver = nil
        }
        // The School Canvas widgets + local ingest endpoint (NIC-132): the Chrome extension POSTs
        // scraped courses/deadlines to the loopback endpoint (bearer-authenticated, loopback-only),
        // which persists them; the publisher reads the store and streams the two widgets, refreshing
        // the instant a scrape lands. All Canvas surfaces are nil when the store can't open, so the
        // widgets fall back to their honest bootstrap state rather than erroring.
        let canvasStore = try? makeCanvasSnapshotStore(paths)
        // The hidden-item list (NIC-132): course/assignment ids the user has manually hidden. Read by
        // the publisher each tick (to filter) and by the settings surface (to list + toggle).
        let canvasHiddenStore = try? makeCanvasHiddenStore(paths)
        let canvasSecretStore = composition.secretStore
        let canvasPort: UInt16 = 8899
        let canvasEndpoint = "http://127.0.0.1:\(canvasPort)/canvas/ingest"
        let canvasPub: CanvasWidgetPublisher? = canvasStore.map { store in
            CanvasWidgetPublisher(
                store: store,
                hiddenIds: { (try? canvasHiddenStore?.hiddenIds()).flatMap { $0 } ?? [] },
                emit: { relay.emit($0) }
            )
        }
        canvasPublisher = canvasPub
        if let canvasStore, let canvas = canvasPub {
            canvasIngestServer = CanvasIngestServer(
                port: canvasPort,
                store: canvasStore,
                token: { await CanvasIngestToken.load(from: canvasSecretStore) },
                onIngest: { Task { await canvas.refresh() } }
            )
            // Mint the ingest token once (idempotent) so the extension can be paired via the token the
            // settings surface shows (Increment 6); a live secret, never logged.
            Task { _ = try? await CanvasIngestToken.ensure(in: canvasSecretStore) }
        } else {
            canvasIngestServer = nil
            Self.log.error("Canvas scrape store failed to open; School widgets + ingest disabled.")
        }
        // The Canvas connect/status surface (NIC-132): `getCanvasStatus` reports the pairing
        // endpoint/token (minting it if needed) + the last scrape's age/counts + the item lists;
        // `resetCanvas` purges the scraped data, clears hides, and rotates the token (disconnect);
        // `setCanvasItemHidden` hides/unhides one item and refreshes the widgets. All nil without a store.
        let canvasStatusClosure: (@Sendable () async -> CanvasStatusInfo)? = canvasStore.map { store in
            { @Sendable in
                let token = try? await CanvasIngestToken.ensure(in: canvasSecretStore)
                let snapshot = (try? store.load()).flatMap { $0 }
                let hidden = (try? canvasHiddenStore?.hiddenIds()).flatMap { $0 } ?? []
                return Self.canvasStatusInfo(
                    snapshot: snapshot, hidden: hidden, endpoint: canvasEndpoint, token: token
                )
            }
        }
        let canvasResetClosure: (@Sendable () async -> CanvasStatusInfo)? = canvasStore.map { store in
            { @Sendable [canvas = canvasPub] in
                try? store.clear()
                try? canvasHiddenStore?.clear() // a disconnect is a clean slate
                let token = try? await CanvasIngestToken.rotate(in: canvasSecretStore)
                if let canvas { await canvas.refresh() }
                return CanvasStatusInfo(
                    endpoint: canvasEndpoint, token: token, lastScrapedAt: nil, courseCount: 0, deadlineCount: 0
                )
            }
        }
        let canvasSetHiddenClosure: (@Sendable (String, Bool) async -> CanvasStatusInfo)?
        if let canvasStore, let hiddenStore = canvasHiddenStore {
            canvasSetHiddenClosure = { [canvas = canvasPub] id, hidden in
                var ids = (try? hiddenStore.hiddenIds()) ?? []
                if hidden { ids.insert(id) } else { ids.remove(id) }
                try? hiddenStore.setHiddenIds(ids)
                if let canvas { await canvas.refresh() } // apply to the widgets immediately
                let token = try? await CanvasIngestToken.ensure(in: canvasSecretStore)
                let snapshot = (try? canvasStore.load()).flatMap { $0 }
                return Self.canvasStatusInfo(
                    snapshot: snapshot, hidden: ids, endpoint: canvasEndpoint, token: token
                )
            }
        } else {
            canvasSetHiddenClosure = nil
        }
        // Feed the layout-display resolver its persisted ids (captured directly, not
        // through `self`, so no not-yet-initialized capture) — the layout arrange
        // reads it live at open time (NIC-142).
        layoutDisplayContext.settingsReader = {
            let stored = try? settingsStore?.load()
            return (layout: stored?.layoutDisplayID, main: stored?.mainDisplayID)
        }
        // The Spotify connect coordinator (NIC-133): the `connectSpotify` op runs its OAuth flow
        // (loopback listener + system browser + code exchange), persisting tokens to the same
        // Keychain the other providers use. The public Client ID is read from the secret store
        // (`spotify_client_id`, entered in Settings) at connect time — absent → an honest "add your
        // Client ID". The tokens never cross back through the bridge; only the granted scope does.
        let spotifyCoordinator = SpotifyAuthCoordinator(secretStore: composition.secretStore)
        let spotifySecretStore = composition.secretStore
        // Which widget ids each mode's left/right slots show (config/modes, through the same
        // layered loader bootstrap composes from) — drives the mode-entry widget refresh below.
        let modeWidgetSlots: [String: Set<String>] = {
            let modes = {
                switch ConfigLoader(workspace: paths).load() {
                case let .activated(config): return config.modes
                case let .rejected(_, lastKnownGood): return lastKnownGood?.modes ?? []
                }
            }()
            return Dictionary(uniqueKeysWithValues: modes.map {
                ($0.id, Set([$0.widgets.widgetsLeft, $0.widgets.widgetsRight]))
            })
        }()
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
                permissions: permissionChecker,
                // The weather producer is composed below (NIC-169), so `weather` reports
                // available once the Location grant is satisfied.
                weatherProviderComposed: true
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
            // Lists the user's calendars for the Settings calendar→mode mapping (NIC-126),
            // driven off listCalendars — the read side of the mapping the schedule producer uses.
            calendarProvider: EventKitCalendarProvider(),
            // Provisions/reads API credentials in the Keychain (NIC-134): storeSecret
            // writes the value, getSecretStatus reports presence — the value never
            // enters config or a log (FR-CFG-03).
            secretStore: composition.secretStore,
            // When a provider key is stored, refresh its producer at once so the widget goes live
            // immediately instead of on its next slow tick: TMDB → releases (NIC-134), Finnhub →
            // stocks (NIC-128).
            onSecretStored: { [news = newsPublisher] reference in
                if reference == "tmdb_api_key" { Task { await releases.refresh() } }
                if reference == "finnhub_api_key" { Task { await stocks.refresh() } }
                if reference == "newsdata_api_key", let news { Task { await news.refresh() } }
                if reference == "github_api_token" { Task { await projectGitStatus.refresh() } }
            },
            // When a settings field changes, refresh the producer it drives so the edit is live at
            // once rather than on its next tick: the tracked-ticker list → stocks (NIC-128), the
            // calendar→mode map → the schedule (NIC-126).
            onSettingsChanged: { [calendar = calendarPublisher] changes in
                if changes.stockTickersJSON != nil { Task { await stocks.refresh() } }
                if changes.calendarModeMapJSON != nil, let calendar { Task { await calendar.refresh() } }
            },
            // A mode switch refreshes the entered mode's widget producers at once (its
            // widgets.left/right slots from config/modes), so the rail shows fresh data on
            // entry — e.g. Developer re-pulls GitHub, Entertainment re-polls Spotify —
            // rather than each producer's last cadence tick. The all-mode regions
            // (schedule, news, weather, system health) keep their own cadences: they are
            // already streaming on every mode, and re-fetching metered providers on every
            // switch would burn API quota for no fresher data.
            onModeApplied: { [canvas = canvasPub] modeID in
                let slots = modeWidgetSlots[modeID] ?? []
                if slots.contains("project-git-status") { Task { await projectGitStatus.refresh() } }
                if slots.contains("repositories") { Task { await repos.refresh() } }
                if slots.contains("projects") { Task { await projects.refresh() } }
                if slots.contains("stocks") { Task { await stocks.refresh() } }
                if slots.contains("spotify") { Task { await spotify.refresh() } }
                if slots.contains("releases") { Task { await releases.refresh() } }
                // One refresh covers both School widgets — the Canvas producer emits both.
                if let canvas, !slots.isDisjoint(with: ["deadlines", "courses"]) {
                    Task { await canvas.refresh() }
                }
            },
            // Runs the Spotify OAuth connect flow for the `connectSpotify` op (NIC-133): reads the
            // public Client ID from the Keychain, then drives the coordinator's browser round trip.
            // A missing/blank Client ID surfaces as an honest "add your Client ID" (credentialsMissing).
            spotifyConnect: {
                let clientID: String
                do {
                    clientID = try await spotifySecretStore.readValue(reference: "spotify_client_id")
                } catch {
                    throw SpotifyPlaybackError.credentialsMissing
                }
                let trimmed = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { throw SpotifyPlaybackError.credentialsMissing }
                let connection = try await spotifyCoordinator.connect(clientID: trimmed)
                // Tokens are stored — emit a now-playing sample at once so the widget goes live
                // immediately rather than on the publisher's next tick.
                await spotify.refresh()
                return SpotifyConnectionInfo(scope: connection.scope)
            },
            // The `git-clone` form's location field (quick-actions phase 4): a native folder
            // picker rooted at the projects root. The chooser — not the caller — decides where the
            // panel opens and refuses a selection outside that root, so the tool's containment
            // guarantee is never delegated to the web layer. Main actor: it presents a panel.
            chooseFolder: {
                await MainActor.run { ProjectsFolderChooser() }.choose()
            },
            // The Canvas connect/status surface (NIC-132): getCanvasStatus shows the pairing
            // endpoint/token + last-scrape summary; resetCanvas purges the scrape and rotates the token.
            canvasStatus: canvasStatusClosure,
            canvasReset: canvasResetClosure,
            canvasSetHidden: canvasSetHiddenClosure,
            // Rebuilds the derived note index from the durable Markdown (NIC-163). The user reaches
            // this from Setup → Library after editing notes in another editor — the index only
            // learns about those files when it is rebuilt. Composed through the shared
            // `makeKnowledgeService`, so it reads the same root the runtime writes to, including a
            // re-pointed one (NIC-138). Runs off the main actor: a large vault is a filesystem walk.
            knowledgeRebuild: {
                try await Task.detached(priority: .userInitiated) {
                    let knowledge = try makeKnowledgeService(paths)
                    return KnowledgeRebuildInfo(root: knowledge.rootPath, noteCount: try knowledge.rebuild())
                }.value
            },
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
            permissions: permissionChecker,
            // Re-derive weather too: granting Location in System Settings flips it available
            // live on the next app-active recheck (NIC-169/NIC-83).
            weatherProviderComposed: true
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

    /// Start the live streams — system metrics (NIC-81b) and the active-repos widget
    /// (NIC-131). Call once the event sink is bound, so the first snapshot of each has a
    /// consumer.
    /// Builds the Canvas status from the latest snapshot + hidden set (NIC-132): the item lists carry
    /// every scraped course/assignment with its hidden flag, and the counts are the VISIBLE totals.
    private static func canvasStatusInfo(
        snapshot: CanvasScrapeSnapshot?, hidden: Set<String>, endpoint: String, token: String?
    ) -> CanvasStatusInfo {
        let courses = (snapshot?.courses ?? []).map {
            CanvasStatusItem(id: $0.id, label: $0.name, hidden: hidden.contains($0.id))
        }
        let deadlines = (snapshot?.deadlines ?? []).map {
            CanvasStatusItem(id: $0.id, label: $0.title, hidden: hidden.contains($0.id))
        }
        return CanvasStatusInfo(
            endpoint: endpoint,
            token: token,
            lastScrapedAt: snapshot.map { ISO8601DateFormatter().string(from: $0.scrapedAt) },
            courseCount: courses.filter { !$0.hidden }.count,
            deadlineCount: deadlines.filter { !$0.hidden }.count,
            courses: courses,
            deadlines: deadlines
        )
    }

    func startStatusPublishing() {
        let metrics = statusPublisher
        let repos = reposPublisher
        let projects = projectsPublisher
        let weather = weatherPublisher
        let releases = releasesPublisher
        let stocks = stocksPublisher
        let news = newsPublisher
        let calendar = calendarPublisher
        let projectGitStatus = projectGitStatusPublisher
        let spotify = spotifyPublisher
        Task { await metrics.start() }
        Task { await repos.start() }
        Task { await projects.start() }
        Task { await weather.start() }
        Task { await releases.start() }
        Task { await stocks.start() }
        if let news { Task { await news.start() } }
        if let calendar { Task { await calendar.start() } }
        Task { await projectGitStatus.start() }
        Task { await spotify.start() }
        if let canvas = canvasPublisher { Task { await canvas.start() } }
        // Bind the Canvas ingest endpoint (NIC-132) once the app is up. Failing to bind (e.g. the
        // port is taken) disables ingest without affecting the rest of the bridge.
        if let canvasServer = canvasIngestServer { Task { _ = try? await canvasServer.start() } }
    }

    /// Pause/resume the live streams from the shell's visibility signal (dashboard
    /// occluded → no sampling; MAC-ADAPTER-3 battery AC). Both the metrics and
    /// active-repos producers share this gate.
    func setStatusPublishingActive(_ active: Bool) {
        let metrics = statusPublisher
        let repos = reposPublisher
        let projects = projectsPublisher
        let weather = weatherPublisher
        let releases = releasesPublisher
        let stocks = stocksPublisher
        let news = newsPublisher
        let calendar = calendarPublisher
        let projectGitStatus = projectGitStatusPublisher
        let spotify = spotifyPublisher
        Task { await metrics.setActive(active) }
        Task { await repos.setActive(active) }
        Task { await projects.setActive(active) }
        Task { await weather.setActive(active) }
        Task { await releases.setActive(active) }
        Task { await stocks.setActive(active) }
        if let news { Task { await news.setActive(active) } }
        if let calendar { Task { await calendar.setActive(active) } }
        Task { await projectGitStatus.setActive(active) }
        Task { await spotify.setActive(active) }
        if let canvas = canvasPublisher { Task { await canvas.setActive(active) } }
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
