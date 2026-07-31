// Streaming Releases widget events (NIC-134) — the Entertainment right-slot producer.
#if canImport(AppKit)
import Foundation
import CerebralCore
import CerebralRuntimeHost
import CerebralTools

/// Resolves the TMDB API token from the Keychain, fetches trending releases, and emits one
/// `widget.data.changed` event for the `releases` widget per tick (NIC-134). The dashboard folds
/// it into `liveWidgets`, which the Entertainment right rail renders (NIC-131 blueprint).
///
/// Mirrors ``WeatherPublisher``'s battery/visibility discipline on a **slow cadence** (default
/// 30 min — trending changes slowly and each tick makes a network request): the loop is
/// deactivated while the dashboard is not visible (the shell flips `setActive` from occlusion
/// state) and reactivation emits immediately. When no key is stored the tick emits an honest
/// "add your API key" state rather than a fabricated list (FR-CFG-03); a provider/network
/// failure emits a generic unavailable. The token is read per tick, so adding or replacing the
/// key in Settings takes effect on the next tick without a relaunch.
public actor ReleasesPublisher {
    private let secretStore: any SecretStoreManaging
    private let provider: any ReleaseProvider
    private let reference: String
    private let intervalNanos: UInt64
    private let emit: @Sendable (String) -> Void

    private var loop: Task<Void, Never>?
    private var active = true

    public init(
        secretStore: any SecretStoreManaging,
        provider: any ReleaseProvider,
        reference: String = "tmdb_api_key",
        intervalMs: Int = 1_800_000,
        emit: @escaping @Sendable (String) -> Void
    ) {
        self.secretStore = secretStore
        self.provider = provider
        self.reference = reference
        self.intervalNanos = UInt64(intervalMs) * 1_000_000
        self.emit = emit
    }

    /// Starts the sampling loop (idempotent). The first tick fires immediately, so the widget
    /// populates as soon as the stream starts rather than after one (long) interval.
    public func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.tickIfActive()
                try? await Task.sleep(nanoseconds: self.intervalNanos)
            }
        }
    }

    public func stop() {
        loop?.cancel()
        loop = nil
    }

    /// Emit a fresh sample now, regardless of cadence — used when the user just stored the API
    /// key (NIC-134), so the widget goes live immediately instead of waiting out the 30-min
    /// interval. The token is re-read this tick, so a newly entered key is picked up at once.
    public func refresh() async {
        await tick()
    }

    /// Pause/resume from the shell's visibility signal. Resuming emits a fresh sample
    /// immediately instead of waiting out the current interval.
    public func setActive(_ nowActive: Bool) async {
        let wasActive = active
        active = nowActive
        if nowActive && !wasActive {
            await tick()
        }
    }

    private func tickIfActive() async {
        guard active else { return }
        await tick()
    }

    private func tick() async {
        let result: Swift.Result<[ReleaseItem], Error>
        do {
            let token = try await secretStore.readValue(reference: reference)
            let items = try await provider.trending(apiToken: token)
            result = .success(items)
        } catch {
            // A missing keychain entry → guide the user to add the key; any other failure
            // (denied keychain, provider/network) → a generic honest unavailable.
            if let native = error as? NativeCapabilityError, case .notFound = native {
                result = .failure(ReleaseError.credentialsMissing)
            } else {
                result = .failure(error)
            }
        }

        let widget = BridgeEventFactory.releasesWidget(from: result, now: Date())
        let event = BridgeEventFactory.widgetDataChangedEvent(
            widgetId: "releases",
            widget: widget,
            id: BridgeEventFactory.newEventID(),
            timestamp: Date()
        )
        guard
            let data = try? BridgeMessageCoding.encoder().encode(event),
            let json = String(data: data, encoding: .utf8)
        else { return }
        emit(json)
    }
}
#endif
