import Foundation
import CerebralContracts
import CerebralCore
import CerebralTools

/// Executes versioned bridge operation requests against the live ``CommandRuntime``
/// (NIC-74b, ADR-004). Transport-agnostic: the WKWebView transport (or a test) hands
/// it a decoded operation request and forwards the response it returns.
///
/// This increment maps the command-style operations — `submitCommand` and
/// `applyMode` — onto `CommandRuntime.submit`. The structured knowledge/confirmation/
/// settings operations, `getBootstrapState`, `getRecentActivity`, and the event
/// stream land in following increments; until then they return a structured
/// `unavailable_capability` error so the dashboard degrades honestly rather than
/// hanging on a missing reply.
public final class BridgeSession: @unchecked Sendable {
    private let runtime: CommandRuntime
    private let configDirectory: URL
    /// The full workspace, when the host has one (the shell). Enables the
    /// user-overrides read side (bootstrap composes through `ConfigLoader`, so
    /// pinned quick apps appear — NIC-119c) and the validated override write
    /// path. nil = shipped-defaults composition (tests, workspace-less hosts).
    private let workspace: WorkspacePaths?
    /// Durable settings persistence (FR-CFG-04). Optional so a host without a
    /// database binding (some tests) still validates patches; when absent, an
    /// accepted patch is validated but not saved — the pre-store behavior.
    private let settingsStore: (any SettingsStore)?
    /// The durable active-mode store (FR-MOD-05). When bound, bootstrap restores
    /// the last active mode; when absent, the stored default applies.
    private let modeStateStore: (any ModeStateStore)?
    /// The composed capability flags the handshake reports (FR-SHL-06), derived at
    /// composition time from the bound capability bundle, phase, and platform
    /// permissions (``CompositionCapabilities``). Defaults to the honest pre-Mac
    /// mock set: every native capability unavailable. Mutable because permission
    /// state can change while running (NIC-83) — the shell rechecks on activation
    /// and updates via ``updateCapabilities(_:)``.
    public var capabilities: [CerebralContracts.Capability] {
        capabilitiesLock.lock()
        defer { capabilitiesLock.unlock() }
        return currentCapabilities
    }

    private let capabilitiesLock = NSLock()
    private var currentCapabilities: [CerebralContracts.Capability]
    private let messageSchemaVersion = "1.0.0"
    /// Emits an already-encoded bridge-event JSON string to the dashboard (Sendable
    /// String — no non-Sendable DTO crosses the transport boundary).
    private let emitEventJSON: @Sendable (String) -> Void

    /// Pending confirmations awaiting a decision, keyed by disclosure id
    /// (== `ConfirmationToken.confirmationID`). The token is a single-use secret held
    /// only here; the dashboard decides by id and never sees the token.
    private let tokenLock = NSLock()
    private var pendingTokens: [String: ConfirmationToken] = [:]

    /// Fetches site favicons for URL quick apps (NIC-147). Optional: a host without
    /// it (tests, workspace-less hosts) simply serves URL tiles without favicons.
    /// The fetch runs in the background off `listUrls`/`addUrlReference`; results are
    /// cached under the state root and pushed live via `mode.quickapps.changed`.
    private let faviconCapability: (any FaviconCapability)?
    /// Origins with an in-flight favicon fetch, so overlapping `listUrls` calls never
    /// crawl the same site twice concurrently.
    private let faviconLock = NSLock()
    private var faviconInFlightOrigins: Set<String> = []

    public init(
        runtime: CommandRuntime,
        configDirectory: URL,
        workspace: WorkspacePaths? = nil,
        capabilities: [CerebralContracts.Capability] = CompositionCapabilities.bridgeCapabilities(phase: .preMac, nativeCapabilityIDs: []),
        settingsStore: (any SettingsStore)? = nil,
        modeStateStore: (any ModeStateStore)? = nil,
        faviconCapability: (any FaviconCapability)? = nil,
        emitEventJSON: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        self.runtime = runtime
        self.configDirectory = configDirectory
        self.workspace = workspace
        self.settingsStore = settingsStore
        self.modeStateStore = modeStateStore
        self.faviconCapability = faviconCapability
        self.currentCapabilities = capabilities
        self.emitEventJSON = emitEventJSON
    }

    /// The one composition every snapshot/bootstrap emission uses: through the
    /// layered loader (user overrides included) when a workspace is bound, else
    /// the shipped defaults.
    private func composeState(activeModeID: String?) -> CerebralHelmBridgeBootstrapState {
        // When the live-metrics provider is available a sample is inbound, so the composed
        // System Health region loads (`.empty`) rather than reporting unavailable — the shell
        // shows a same-shape skeleton instead of an "unavailable" flash on first paint or a
        // mode switch (NIC-136). Absent the provider it stays honestly unavailable.
        let metricsExpected = capabilities.first { $0.id == "system.metrics" }?.available == true
        if let workspace {
            return BootstrapComposer.compose(
                workspace: workspace, activeModeID: activeModeID, systemMetricsExpected: metricsExpected
            )
        }
        return BootstrapComposer.compose(
            configDirectory: configDirectory, activeModeID: activeModeID, systemMetricsExpected: metricsExpected
        )
    }

    /// Replaces the reported capability set (a permission recheck, NIC-83) and
    /// returns the capabilities whose availability changed, so the caller can
    /// emit one `bridge.capability.changed` event per transition. Future
    /// handshakes report the updated set.
    public func updateCapabilities(
        _ updated: [CerebralContracts.Capability]
    ) -> [CerebralContracts.Capability] {
        capabilitiesLock.lock()
        defer { capabilitiesLock.unlock() }
        let previousByID = Dictionary(uniqueKeysWithValues: currentCapabilities.map { ($0.id, $0) })
        currentCapabilities = updated
        return updated.filter { capability in
            previousByID[capability.id]?.available != capability.available
        }
    }

    public func execute(
        _ request: CerebralHelmBridgeOperationRequest
    ) async -> CerebralHelmBridgeOperationResponse {
        switch request.operation {
        case .getBootstrapState:
            return ok(request, payload: composeBootstrapState())
        case .submitCommand:
            return await submitCommand(request)
        case .applyMode:
            return await applyMode(request)
        case .captureNote:
            return await captureNote(request)
        case .searchNotes:
            return await searchNotes(request)
        case .getRecentActivity:
            return getRecentActivity(request)
        case .decideConfirmation:
            return await decideConfirmation(request)
        case .updateSettings:
            return updateSettings(request)
        case .listApps:
            return await listApps(request)
        case .updateQuickApps:
            return updateQuickApps(request)
        case .addURLReference:
            return addUrlReference(request)
        case .listUrls:
            return listUrls(request)
        case .runSpeedTest:
            return await runSpeedTest(request)
        case .getSettings:
            return getSettings(request)
        default:
            // captureNote (confirmation-gated local_write returning a synchronous
            // noteId) and subscribe follow later.
            return unimplemented(request)
        }
    }

    // MARK: - Operations

    private func submitCommand(
        _ request: CerebralHelmBridgeOperationRequest
    ) async -> CerebralHelmBridgeOperationResponse {
        guard let input: SubmitCommandInput = decodePayload(request), !input.rawInput.isEmpty else {
            return invalidInput(request, "submitCommand requires a non-empty rawInput.")
        }
        // Honor an explicit, known source; default to `dashboard`. This keeps the
        // command bus honest about provenance (FR-CMD-01) without trusting arbitrary
        // strings.
        let source = input.source.flatMap(CommandSource.init(rawValue:)) ?? .dashboard
        let outcome = await runtime.submit(input.rawInput, source: source)
        registerAwaitingConfirmation(outcome)
        emitConfigChangedIfModeApplied(outcome)
        return ok(request, payload: receipt(for: outcome))
    }

    /// A raw `mode <id>` command (palette, CLI-over-bridge) that succeeded also
    /// re-themes the dashboard, exactly like the `applyMode` operation — one
    /// switch, one visible result, regardless of which surface asked.
    private func emitConfigChangedIfModeApplied(_ outcome: CommandRuntimeOutcome) {
        guard
            case let .completed(_, status, result) = outcome,
            status == .succeeded,
            let result, result.toolID == "mode.apply",
            let output = result.output,
            let decoded = try? CerebralHelmModeApplyOutput(data: output)
        else { return }
        let snapshot = composeState(activeModeID: decoded.modeID)
        emit(BridgeEventFactory.configChangedEvent(
            snapshot: snapshot, id: BridgeEventFactory.newEventID(), timestamp: Date()
        ))
    }

    private func applyMode(
        _ request: CerebralHelmBridgeOperationRequest
    ) async -> CerebralHelmBridgeOperationResponse {
        guard let input: ApplyModeInput = decodePayload(request), !input.modeId.isEmpty else {
            return invalidInput(request, "applyMode requires a modeId.")
        }
        guard BootstrapComposer.modeExists(input.modeId, configDirectory: configDirectory) else {
            return ok(request, payload: ApplyModeResult(modeId: input.modeId, status: "error"))
        }
        // A mode switch is a real command: `mode.apply` persists the active mode
        // and records a session (FR-MOD-05/06). It runs no workflow steps — the
        // dashboard swap below and the durable switch are the whole effect
        // (workspace re-scope, NIC-85).
        _ = await runtime.submit("mode \(input.modeId)", source: .dashboard)
        // Re-theme the dashboard by emitting the target mode's snapshot.
        let snapshot = composeState(activeModeID: input.modeId)
        emit(BridgeEventFactory.configChangedEvent(
            snapshot: snapshot, id: BridgeEventFactory.newEventID(), timestamp: Date()
        ))
        return ok(request, payload: ApplyModeResult(modeId: input.modeId, status: "ok"))
    }

    private func captureNote(
        _ request: CerebralHelmBridgeOperationRequest
    ) async -> CerebralHelmBridgeOperationResponse {
        guard let input: CaptureNoteInput = decodePayload(request), !input.title.isEmpty else {
            return invalidInput(request, "captureNote requires a title.")
        }
        // note.capture is a confirmation-gated local_write, so this enters the bus and
        // the disclosure is pushed to the UI. The note is written after the user
        // approves; the returned id is the command handle (see the captureNote contract
        // note — a synchronous noteId is not possible for a gated capture).
        let text = input.body.isEmpty ? input.title : "\(input.title)\n\(input.body)"
        let outcome = await runtime.submit("note \(text)", source: .dashboard)
        registerAwaitingConfirmation(outcome)
        switch outcome {
        case let .completed(commandID, _, result):
            if let data = result?.output, let output = try? CerebralHelmNoteCaptureOutput(data: data) {
                return ok(request, payload: CaptureNoteResult(noteId: output.noteID))
            }
            return ok(request, payload: CaptureNoteResult(noteId: commandID))
        case let .awaitingConfirmation(commandID, _, _):
            return ok(request, payload: CaptureNoteResult(noteId: commandID))
        case .rejected:
            return errorResponse(
                request, category: .invalidInput,
                code: "note_rejected", message: "The note could not be parsed."
            )
        }
    }

    private func runSpeedTest(
        _ request: CerebralHelmBridgeOperationRequest
    ) async -> CerebralHelmBridgeOperationResponse {
        // network.speed.test is a read_only tool — it never gates on confirmation,
        // so this resolves synchronously with the measurement (NIC-135). The bounded
        // ~30s networkQuality run happens inside runtime.submit; the caller awaits it
        // while the widget animates its ring.
        let outcome = await runtime.submit("speedtest", source: .dashboard)
        guard case let .completed(_, _, result) = outcome,
              let data = result?.output,
              let output = try? CerebralHelmNetworkSpeedTestOutput(data: data)
        else {
            // The tool could not run, or produced no parseable output: an honest
            // unavailable, never a fabricated figure.
            return ok(request, payload: SpeedTestResult(
                status: "unavailable", downloadMbps: nil, uploadMbps: nil, testedAt: nil
            ))
        }
        return ok(request, payload: SpeedTestResult(
            status: output.status.rawValue,
            downloadMbps: output.downloadMbps,
            uploadMbps: output.uploadMbps,
            testedAt: output.testedAt
        ))
    }

    private func searchNotes(
        _ request: CerebralHelmBridgeOperationRequest
    ) async -> CerebralHelmBridgeOperationResponse {
        guard let input: SearchNotesInput = decodePayload(request), !input.text.isEmpty else {
            // An empty query yields no results rather than an error (empty search box).
            return ok(request, payload: SearchNotesResult(results: []))
        }
        let outcome = await runtime.submit("search \(input.text)", source: .dashboard)
        guard
            case let .completed(_, _, result) = outcome,
            let data = result?.output,
            let output = try? CerebralHelmNoteSearchOutput(data: data)
        else {
            return ok(request, payload: SearchNotesResult(results: []))
        }
        let hits = output.results.map {
            NoteHit(noteId: $0.noteID, title: $0.title, excerpt: $0.excerpt)
        }
        return ok(request, payload: SearchNotesResult(results: hits))
    }

    /// Read-only application discovery (NIC-119): wraps the `apps` command so the
    /// More Apps picker rides the same command bus as every other input source,
    /// and unwraps the tool output for the dashboard. Pre-Mac (or on any tool
    /// failure) this is a structured unavailable — the picker renders honestly.
    private func listApps(
        _ request: CerebralHelmBridgeOperationRequest
    ) async -> CerebralHelmBridgeOperationResponse {
        let outcome = await runtime.submit("apps", source: .dashboard)
        guard
            case let .completed(_, status, result) = outcome,
            status == .succeeded,
            let data = result?.output,
            let output = try? CerebralHelmAppsListOutput(data: data)
        else {
            return errorResponse(
                request, category: .unavailableCapability,
                code: "apps_list_unavailable",
                message: "Application discovery is unavailable."
            )
        }
        // Auto-mint (owner decision, 2026-07-06): any discovered app that no
        // reference targets gets one minted now, so a mid-session install is
        // pinnable immediately. (`open <minted-id>` resolves from the next
        // launch — the parser's references compose at startup.)
        if let workspace {
            let shipped = (try? ReferenceCatalogLoader.load(configDirectory: configDirectory))
                .map { Array($0.apps.values) } ?? []
            UserAppReferences.mint(
                discovered: output.apps.map {
                    UserAppReferences.DiscoveredApp(bundleID: $0.bundleID, name: $0.name)
                },
                shipped: shipped,
                stateRoot: workspace.stateRoot
            )
        }
        // Join discovered apps onto the configured app references by bundle id
        // (the reference `target`). `referenceId` is the pinnable key: only a
        // discovered app backed by a configured reference may enter a mode's
        // quick-app slots (NIC-119 — no arbitrary paths, ever).
        let referencesByTarget = appReferencesByTarget()
        let apps = output.apps.map {
            DiscoveredApp(
                bundleId: $0.bundleID,
                name: $0.name,
                iconPng: $0.iconPNG,
                referenceId: referencesByTarget[$0.bundleID]
            )
        }
        return ok(request, payload: ListAppsResult(apps: apps, truncated: output.truncated))
    }

    /// Sets a mode's quick-app slots through the validated config-write path
    /// (NIC-119c): every id must name a configured app reference (existence
    /// check), then `ConfigOverrideWriter` writes the per-mode override and
    /// re-activates the layered config — a rejected candidate is rolled back on
    /// disk and reported, never half-applied. An applied write emits
    /// `mode.quickapps.changed` so every surface's tiles refresh immediately.
    private func updateQuickApps(
        _ request: CerebralHelmBridgeOperationRequest
    ) -> CerebralHelmBridgeOperationResponse {
        guard let input: UpdateQuickAppsInput = decodePayload(request), !input.modeId.isEmpty else {
            return invalidInput(request, "updateQuickApps requires a modeId and quickApps array.")
        }
        guard let workspace else {
            return errorResponse(
                request, category: .unavailableCapability,
                code: "overrides_unavailable",
                message: "Pinning requires a durable workspace."
            )
        }
        // A quick-app slot may hold any configured app or URL reference id (NIC-146):
        // a pinned URL is just another quick-app tile, so both catalogs are valid
        // pin targets. Arbitrary paths/URLs still can't enter — only ids that name a
        // reference the catalog already resolves.
        let known = configuredReferenceIDs()
        let unknown = input.quickApps.filter { !known.contains($0) }
        guard unknown.isEmpty else {
            return ok(request, payload: UpdateQuickAppsResult(
                accepted: false,
                quickApps: input.quickApps,
                errors: unknown.map { "\"\($0)\" is not a configured app or URL reference." }
            ))
        }

        let override = CerebralHelmModeOverride(
            extensions: nil, id: input.modeId, quickApps: input.quickApps, schemaVersion: "1.0.0"
        )
        switch ConfigOverrideWriter(workspace: workspace).write(override) {
        case .applied:
            // Refresh every surface: a dedicated per-widget event carries the new
            // slots (NIC-149). `config.changed` cannot — its snapshot omits `modes`
            // and the dashboard ignores it when the active mode is unchanged.
            emit(BridgeEventFactory.quickAppsChangedEvent(
                modeId: input.modeId, quickApps: input.quickApps,
                id: BridgeEventFactory.newEventID(), timestamp: Date()
            ))
            return ok(request, payload: UpdateQuickAppsResult(
                accepted: true, quickApps: input.quickApps, errors: []
            ))
        case let .rejected(errors):
            return ok(request, payload: UpdateQuickAppsResult(
                accepted: false,
                quickApps: input.quickApps,
                errors: errors.map(\.message)
            ))
        }
    }

    /// Configured app references keyed by their bundle-id target.
    private func appReferencesByTarget() -> [String: String] {
        guard let references = try? ReferenceCatalogLoader.load(configDirectory: configDirectory, stateRoot: workspace?.stateRoot) else {
            return [:]
        }
        return Dictionary(
            references.apps.values.map { ($0.target, $0.id) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// Every configured reference id the parser resolves — app and URL, shipped and
    /// user-minted. This is the pinnable-id set (`updateQuickApps`, NIC-146) and the
    /// uniqueness domain a newly minted URL id must avoid, so a pinned URL's
    /// `open <id>` can never resolve ambiguously against an app of the same id.
    private func configuredReferenceIDs() -> Set<String> {
        guard let references = try? ReferenceCatalogLoader.load(configDirectory: configDirectory, stateRoot: workspace?.stateRoot) else {
            return []
        }
        return Set(references.apps.keys).union(references.urls.keys)
    }

    /// Mints a user URL reference through the same auto-minting mechanism as user
    /// app references (NIC-146): a user-entered URL becomes a configured reference,
    /// so it can then be pinned as a quick app through the validated write path. Only
    /// `http`/`https` URLs mint — never an arbitrary scheme. Requires a durable
    /// workspace (the state root the user catalog lives under).
    private func addUrlReference(
        _ request: CerebralHelmBridgeOperationRequest
    ) -> CerebralHelmBridgeOperationResponse {
        guard let input: AddUrlReferenceInput = decodePayload(request) else {
            return invalidInput(request, "addUrlReference requires a url.")
        }
        guard let workspace else {
            return errorResponse(
                request, category: .unavailableCapability,
                code: "url_references_unavailable",
                message: "Adding a URL requires a durable workspace."
            )
        }
        switch UserURLReferences.add(
            url: input.url, label: input.label,
            existingIDs: configuredReferenceIDs(), stateRoot: workspace.stateRoot
        ) {
        case let .success(entry):
            // Live-reload the shared catalog so the minted id resolves this session:
            // the runtime's parser (`open <id>`) and — on the macOS shell — the
            // url.open capability map both read the same store (NIC-146). Without this
            // the URL would open only after a relaunch.
            if let fresh = try? ReferenceCatalogLoader.load(
                configDirectory: configDirectory, stateRoot: workspace.stateRoot
            ) {
                runtime.updateReferences(fresh)
            }
            // Kick off the favicon fetch now so the icon is ready by the time the
            // dashboard re-reads `listUrls` after pinning (NIC-147). The minted DTO
            // carries no icon yet — the tile shows its placeholder until it lands.
            warmFavicons([entry])
            return ok(request, payload: AddUrlReferenceResult(
                accepted: true,
                reference: urlReferenceDTO(entry, cache: faviconCache()),
                errors: []
            ))
        case let .failure(error):
            return ok(request, payload: AddUrlReferenceResult(
                accepted: false, reference: nil, errors: [Self.message(for: error)]
            ))
        }
    }

    private static func message(for error: UserURLReferences.AddError) -> String {
        switch error {
        case .emptyURL: return "Enter a URL to add."
        case .invalidURL: return "That doesn't look like a valid web address."
        case .unsupportedScheme: return "Only http and https web addresses can be added."
        }
    }

    /// The configured URL references (shipped + user-minted), sorted by label — the
    /// dashboard's read feed for rendering pinned URL tiles with their real labels
    /// (NIC-146). Apps have `listApps` discovery for this; URLs have no discovery,
    /// so this is their equivalent. Workspace-less hosts still see the shipped set.
    private func listUrls(
        _ request: CerebralHelmBridgeOperationRequest
    ) -> CerebralHelmBridgeOperationResponse {
        let urls = (try? ReferenceCatalogLoader.load(
            configDirectory: configDirectory, stateRoot: workspace?.stateRoot
        )).map { Array($0.urls.values) } ?? []
        let cache = faviconCache()
        let sorted = urls
            .sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
            .map { urlReferenceDTO($0, cache: cache) }
        // Warm any cold favicons in the background; a landed icon upgrades its tile
        // live via `mode.quickapps.changed` (NIC-147). The read returns immediately.
        warmFavicons(urls)
        return ok(request, payload: ListUrlsResult(urls: sorted))
    }

    // MARK: - Favicons (NIC-147)

    private func faviconCache() -> FaviconCache? {
        workspace.map { FaviconCache(directory: $0.faviconCacheDirectory) }
    }

    private func urlReferenceDTO(_ entry: ReferenceEntry, cache: FaviconCache?) -> UrlReferenceDTO {
        UrlReferenceDTO(
            id: entry.id, label: entry.label, target: entry.target,
            iconPng: cache?.icon(forTarget: entry.target)?.base64EncodedString()
        )
    }

    /// Fetches, in the background, the favicon for every reference whose origin has
    /// no cached hit or fresh miss — skipping origins already in flight. On success
    /// the PNG is cached and a `mode.quickapps.changed` event nudges the tiles to
    /// re-read `listUrls` (NIC-147 owner decision: reuse the per-widget event, so a
    /// freshly pinned URL shows its placeholder at once and upgrades once fetched).
    /// No-op without a favicon capability or a durable workspace.
    private func warmFavicons(_ references: [ReferenceEntry]) {
        guard let capability = faviconCapability, let cache = faviconCache() else { return }
        // One representative target per cold origin (favicons are per-origin).
        var targetByOrigin: [String: String] = [:]
        for entry in references {
            guard
                let origin = FaviconCache.origin(forTarget: entry.target),
                cache.needsFetch(forTarget: entry.target),
                targetByOrigin[origin] == nil
            else { continue }
            targetByOrigin[origin] = entry.target
        }
        let work = claimFaviconOrigins(Set(targetByOrigin.keys))
            .compactMap { origin in targetByOrigin[origin].map { (origin, $0) } }
        guard !work.isEmpty else { return }

        Task { [weak self] in
            guard let self else { return }
            var anyStored = false
            for (origin, target) in work {
                defer { self.releaseFaviconOrigin(origin) }
                guard let url = URL(string: target) else { continue }
                if let png = await capability.fetchFavicon(for: url) {
                    if cache.store(png: png, forTarget: target) { anyStored = true }
                } else {
                    cache.recordMiss(forTarget: target)
                }
            }
            if anyStored { self.emitFaviconRefresh() }
        }
    }

    /// Marks the given origins in flight and returns those not already fetching.
    private func claimFaviconOrigins(_ origins: Set<String>) -> [String] {
        faviconLock.lock(); defer { faviconLock.unlock() }
        let fresh = origins.subtracting(faviconInFlightOrigins)
        faviconInFlightOrigins.formUnion(fresh)
        return Array(fresh)
    }

    private func releaseFaviconOrigin(_ origin: String) {
        faviconLock.lock(); defer { faviconLock.unlock() }
        faviconInFlightOrigins.remove(origin)
    }

    /// Re-emits the active mode's `mode.quickapps.changed` (unchanged pins) so its
    /// tiles re-read `listUrls` and pick up newly cached favicons. Other modes pick
    /// theirs up on next view — `listUrls` reads the now-warm cache.
    private func emitFaviconRefresh() {
        let state = composeBootstrapState()
        let activeID = bootstrapModeID()
        guard let mode = state.modes.first(where: { $0.id == activeID }) ?? state.modes.first else { return }
        emit(BridgeEventFactory.quickAppsChangedEvent(
            modeId: mode.id, quickApps: mode.quickApps,
            id: BridgeEventFactory.newEventID(), timestamp: Date()
        ))
    }

    /// The recent-activity read surface. A fresh session has no activity; the durable
    /// DB-backed history read is a follow-on increment, so this returns the honest
    /// empty envelope (the dashboard renders an empty feed rather than fabricated rows).
    private func getRecentActivity(
        _ request: CerebralHelmBridgeOperationRequest
    ) -> CerebralHelmBridgeOperationResponse {
        ok(request, payload: RecentActivityEnvelope())
    }

    private func decideConfirmation(
        _ request: CerebralHelmBridgeOperationRequest
    ) async -> CerebralHelmBridgeOperationResponse {
        guard let input: DecideConfirmationInput = decodePayload(request), !input.id.isEmpty else {
            return invalidInput(request, "decideConfirmation requires an id and decision.")
        }
        guard let token = takeToken(id: input.id) else {
            return errorResponse(
                request, category: .invalidInput,
                code: "unknown_confirmation", message: "No pending confirmation for \(input.id)."
            )
        }
        // Only approve/cancel cross the bridge; anything else fails closed as cancel.
        let decision: ConfirmationDecision = (input.decision == "approve") ? .approve : .cancel
        _ = await runtime.decide(token: token, decision: decision)
        // Clear the active confirmation in the UI; the command's own completion/cancel
        // is carried by the lifecycle event stream.
        emit(BridgeEventFactory.confirmationEvent(disclosure: nil, id: BridgeEventFactory.newEventID(), timestamp: Date()))
        return ok(request, payload: DecideConfirmationResult(confirmationId: input.id, decision: input.decision))
    }

    /// Validates a settings patch against the deterministic allowlist (ADR-003) and
    /// persists an accepted patch through the settings store: unknown or
    /// policy-weakening keys are rejected before anything is saved, and a store
    /// failure is a structured error — `accepted` is never reported for a patch
    /// that did not become durable (FR-CFG-04).
    private func updateSettings(
        _ request: CerebralHelmBridgeOperationRequest
    ) -> CerebralHelmBridgeOperationResponse {
        guard
            let data = try? JSONEncoder().encode(request.payload),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let patch = object["patch"] as? [String: Any]
        else {
            return invalidInput(request, "updateSettings requires a patch.")
        }
        let changes = (patch["changes"] as? [String: Any]) ?? [:]
        let errors = SettingsPatchValidator.validate(changes: changes)
        guard errors.isEmpty else {
            return ok(request, payload: UpdateSettingsResult(accepted: false))
        }
        let settingsChanges = SettingsChanges(validatedChanges: changes)
        if let settingsStore {
            do {
                try settingsStore.apply(settingsChanges)
            } catch {
                return errorResponse(
                    request, category: .internalFailure,
                    code: "settings_not_saved",
                    message: "The settings change could not be saved."
                )
            }
            // Live policy re-arm (NIC-137): a change to "Ask before all actions" takes
            // effect immediately for the next command, not just on next launch.
            if let confirmAll = settingsChanges.confirmAllActions {
                runtime.updateConfirmAllActions(confirmAll)
            }
            // Live cross-webview sync: every surface (dashboard + the separate native
            // settings window) reflects the new assistant name, mode colors, and motion
            // preference immediately, not just on next launch.
            emit(BridgeEventFactory.settingsChangedEvent(
                snapshot: resolvedSettingsSnapshot(),
                id: BridgeEventFactory.newEventID(), timestamp: Date()
            ))
        }
        return ok(request, payload: UpdateSettingsResult(accepted: true))
    }

    /// Reads the durable settings on demand so the settings UI initializes its
    /// controls from persisted state rather than hardcoded defaults (NIC-141). This
    /// is the read side of `updateSettings`; effective defaults are resolved in one
    /// deterministic place (``EffectiveSettings``).
    ///
    /// It never errors: a store load failure or a workspace-less host with no store
    /// bound (some tests) yields the effective defaults, mirroring how bootstrap
    /// degrades a missing stored default to the configured default mode. The
    /// configured default mode id is read through the same layered/shipped config
    /// path bootstrap uses — the "default mode" setting, distinct from the currently
    /// active mode.
    private func getSettings(
        _ request: CerebralHelmBridgeOperationRequest
    ) -> CerebralHelmBridgeOperationResponse {
        ok(request, payload: resolvedSettingsSnapshot())
    }

    /// The effective settings snapshot — the single resolution shared by `getSettings`
    /// (the read) and the `settings.changed` event (live sync after a write).
    private func resolvedSettingsSnapshot() -> CerebralHelmSettingsSnapshot {
        let stored = (try? settingsStore?.load()).flatMap { $0 } ?? StoredSettings()
        let configDefaultModeID: String?
        if let workspace {
            configDefaultModeID = BootstrapComposer.defaultModeID(workspace: workspace)
        } else {
            configDefaultModeID = BootstrapComposer.defaultModeID(configDirectory: configDirectory)
        }
        return EffectiveSettings.resolve(stored: stored, configDefaultModeID: configDefaultModeID)
    }

    /// The bootstrap state with mode restore applied (FR-MOD-05). This is the
    /// single composition every surface must use — the `getBootstrapState`
    /// operation and the shell's synchronous `window.__cerebralBootstrap`
    /// injection — so a restored mode can never differ by transport.
    public func composeBootstrapState() -> CerebralHelmBridgeBootstrapState {
        composeState(activeModeID: bootstrapModeID())
    }

    /// The mode bootstrap should activate: the last active mode when it still
    /// exists in config (FR-MOD-05 restart restore), else the stored default
    /// mode, else `nil` for the configured default. Stale references fall back,
    /// never error.
    private func bootstrapModeID() -> String? {
        if let store = modeStateStore,
           let lastActive = try? store.loadActiveModeID(),
           BootstrapComposer.modeExists(lastActive, configDirectory: configDirectory) {
            return lastActive
        }
        guard
            let store = settingsStore,
            let settings = try? store.load(),
            let stored = settings.defaultModeID,
            BootstrapComposer.modeExists(stored, configDirectory: configDirectory)
        else { return nil }
        return stored
    }

    // MARK: - Confirmation flow

    /// When a command pauses for confirmation, remember its single-use token and push
    /// the policy-owned disclosure to the dashboard as a `confirmation.changed` event.
    private func registerAwaitingConfirmation(_ outcome: CommandRuntimeOutcome) {
        guard case let .awaitingConfirmation(_, disclosure, token) = outcome else { return }
        tokenLock.lock()
        pendingTokens[token.confirmationID] = token
        tokenLock.unlock()
        emit(BridgeEventFactory.confirmationEvent(
            disclosure: disclosure, id: BridgeEventFactory.newEventID(), timestamp: Date()
        ))
    }

    private func takeToken(id: String) -> ConfirmationToken? {
        tokenLock.lock(); defer { tokenLock.unlock() }
        return pendingTokens.removeValue(forKey: id)
    }

    private func emit(_ event: CerebralHelmBridgeEvent) {
        guard let data = try? BridgeMessageCoding.encoder().encode(event),
              let json = String(data: data, encoding: .utf8) else { return }
        emitEventJSON(json)
    }

    // MARK: - Payload mapping

    private struct SubmitCommandInput: Decodable {
        let rawInput: String
        let source: String?
    }
    private struct CommandReceipt: Encodable {
        let commandId: String
        let accepted: Bool
    }
    private struct ApplyModeInput: Decodable {
        let modeId: String
    }
    private struct ApplyModeResult: Encodable {
        let modeId: String
        let status: String
    }
    private struct CaptureNoteInput: Decodable {
        let title: String
        let body: String
        let kind: String?
    }
    private struct CaptureNoteResult: Encodable {
        let noteId: String
    }
    private struct SearchNotesInput: Decodable {
        let text: String
        let limit: Int?
    }
    private struct NoteHit: Encodable {
        let noteId: String
        let title: String
        let excerpt: String
    }
    private struct SearchNotesResult: Encodable {
        let results: [NoteHit]
    }
    private struct DecideConfirmationInput: Decodable {
        let id: String
        let decision: String
    }
    private struct DecideConfirmationResult: Encodable {
        let confirmationId: String
        let decision: String
    }
    private struct UpdateSettingsResult: Encodable {
        let accepted: Bool
    }
    private struct DiscoveredApp: Encodable {
        let bundleId: String
        let name: String
        let iconPng: String?
        /// The configured app reference this bundle id backs (nil = not pinnable).
        let referenceId: String?
    }
    private struct ListAppsResult: Encodable {
        let apps: [DiscoveredApp]
        let truncated: Bool
    }
    private struct SpeedTestResult: Encodable {
        /// "ok" | "partial" | "unavailable" (mirrors the tool output).
        let status: String
        let downloadMbps: Double?
        let uploadMbps: Double?
        let testedAt: String?
    }
    private struct UpdateQuickAppsInput: Decodable {
        let modeId: String
        let quickApps: [String]
    }
    private struct UpdateQuickAppsResult: Encodable {
        let accepted: Bool
        let quickApps: [String]
        let errors: [String]
    }
    private struct AddUrlReferenceInput: Decodable {
        let url: String
        let label: String?
    }
    /// A configured URL reference, as delivered to the dashboard (NIC-146). `iconPng`
    /// is the site's cached favicon as base64 PNG (NIC-147), omitted when none is
    /// cached yet — the tile shows its placeholder glyph and upgrades live once the
    /// background fetch lands (`encodeIfPresent` drops the nil, mirroring app icons).
    private struct UrlReferenceDTO: Encodable {
        let id: String
        let label: String
        let target: String
        let iconPng: String?
    }
    private struct AddUrlReferenceResult: Encodable {
        let accepted: Bool
        /// The minted (or already-existing) reference when accepted; nil on rejection.
        let reference: UrlReferenceDTO?
        let errors: [String]
    }
    private struct ListUrlsResult: Encodable {
        let urls: [UrlReferenceDTO]
    }
    /// Mirrors the bridge `getRecentActivity` payload wrapper `{ recentActivity: … }`.
    private struct RecentActivityEnvelope: Encodable {
        let recentActivity = Activity()
        struct Activity: Encodable {
            let commands: [String] = []
            let toolCalls: [String] = []
            let confirmations: [String] = []
            let modeSessions: [String] = []
            let errors: [String] = []
        }
    }

    private func receipt(for outcome: CommandRuntimeOutcome) -> CommandReceipt {
        switch outcome {
        case let .completed(commandID, _, _):
            return CommandReceipt(commandId: commandID, accepted: true)
        case let .awaitingConfirmation(commandID, _, _):
            return CommandReceipt(commandId: commandID, accepted: true)
        case .rejected:
            return CommandReceipt(commandId: "", accepted: false)
        }
    }

    private func decodePayload<T: Decodable>(_ request: CerebralHelmBridgeOperationRequest) -> T? {
        guard let data = try? JSONEncoder().encode(request.payload) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func encodePayload<T: Encodable>(_ value: T) -> [String: JSONAny] {
        guard
            let data = try? JSONEncoder().encode(value),
            let payload = try? JSONDecoder().decode([String: JSONAny].self, from: data)
        else { return [:] }
        return payload
    }

    // MARK: - Responses

    private func ok<T: Encodable>(
        _ request: CerebralHelmBridgeOperationRequest, payload: T
    ) -> CerebralHelmBridgeOperationResponse {
        CerebralHelmBridgeOperationResponse(
            error: nil,
            messageID: request.messageID,
            operation: request.operation,
            payload: encodePayload(payload),
            schemaVersion: messageSchemaVersion,
            status: .ok,
            type: .bridgeOperationResponse
        )
    }

    private func errorResponse(
        _ request: CerebralHelmBridgeOperationRequest,
        category: CerebralContracts.Category,
        code: String,
        message: String
    ) -> CerebralHelmBridgeOperationResponse {
        CerebralHelmBridgeOperationResponse(
            error: CerebralHelmBridgeOperationResponseError(
                category: category, code: code, details: nil, message: message, remediation: nil
            ),
            messageID: request.messageID,
            operation: request.operation,
            payload: [:],
            schemaVersion: messageSchemaVersion,
            status: .error,
            type: .bridgeOperationResponse
        )
    }

    private func invalidInput(
        _ request: CerebralHelmBridgeOperationRequest, _ message: String
    ) -> CerebralHelmBridgeOperationResponse {
        errorResponse(request, category: .invalidInput, code: "bridge_invalid_input", message: message)
    }

    private func unimplemented(
        _ request: CerebralHelmBridgeOperationRequest
    ) -> CerebralHelmBridgeOperationResponse {
        errorResponse(
            request,
            category: .unavailableCapability,
            code: "bridge_operation_unimplemented",
            message: "This bridge operation is not wired to the runtime yet."
        )
    }
}
