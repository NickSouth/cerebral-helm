// Streaming News events (NIC-127) — the bottom-left News panel producer, per relevance profile.
#if canImport(AppKit)
import Foundation
import CerebralCore
import CerebralRuntimeHost
import CerebralTools

/// Resolves the NewsData API key from the Keychain and emits one `news.changed` event **per
/// relevance profile** each tick (NIC-127). The dashboard folds each into its `liveNews` map keyed
/// by `newsProfile`, and the News panel renders the headlines for the active mode's profile
/// (surviving mode switches by construction — NIC-131 blueprint generalized to a per-profile map).
///
/// News is per-mode, so unlike the single-value weather/releases producers this fans out over the
/// distinct profiles the config declares (typically four). Mirrors ``ReleasesPublisher``'s
/// battery/visibility discipline on a **slow cadence** (default 60 min): the loop is deactivated
/// while the dashboard is not visible, and reactivation emits immediately. The token is read once
/// per tick and shared across the profiles' fetches (one Keychain read, N requests). When no key is
/// stored every profile emits an honest "add your API key" state rather than a fabricated list
/// (FR-CFG-03); a provider/network failure emits a generic unavailable. The token is re-read each
/// tick, so adding or replacing the key in Settings takes effect on the next tick without a
/// relaunch.
///
/// API budget note: NewsData's free tier is ~200 requests/day. At 60 min × N profiles this is
/// ~24·N requests/day (≈96 for four profiles), comfortably under the cap; a visibility resume adds
/// one extra tick's worth.
public actor NewsPublisher {
    private let profiles: [String]
    private let secretStore: any SecretStoreManaging
    private let provider: any NewsProvider
    private let reference: String
    private let intervalNanos: UInt64
    private let emit: @Sendable (String) -> Void

    private var loop: Task<Void, Never>?
    private var active = true

    public init(
        profiles: [String],
        secretStore: any SecretStoreManaging,
        provider: any NewsProvider,
        reference: String = "newsdata_api_key",
        intervalMs: Int = 3_600_000,
        emit: @escaping @Sendable (String) -> Void
    ) {
        self.profiles = profiles
        self.secretStore = secretStore
        self.provider = provider
        self.reference = reference
        self.intervalNanos = UInt64(intervalMs) * 1_000_000
        self.emit = emit
    }

    /// Starts the sampling loop (idempotent). The first tick fires immediately, so the panel
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

    /// Emit a fresh sample now, regardless of cadence — used when the user just stored the API key,
    /// so the panel goes live immediately instead of waiting out the interval.
    public func refresh() async {
        await tick()
    }

    /// Pause/resume from the shell's visibility signal. Resuming emits a fresh sample immediately.
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
        guard !profiles.isEmpty else { return }
        // Read the token once and reuse it across every profile's fetch (one Keychain read).
        let token: Swift.Result<String, Error>
        do {
            token = .success(try await secretStore.readValue(reference: reference))
        } catch {
            token = .failure(error)
        }

        for profile in profiles {
            let result: Swift.Result<[NewsHeadline], Error>
            switch token {
            case let .failure(error):
                // A missing keychain entry → guide the user to add the key; any other failure
                // (denied keychain) → a generic honest unavailable.
                if let native = error as? NativeCapabilityError, case .notFound = native {
                    result = .failure(NewsError.credentialsMissing)
                } else {
                    result = .failure(error)
                }
            case let .success(value):
                do {
                    result = .success(try await provider.headlines(profile: profile, apiToken: value))
                } catch {
                    result = .failure(error)
                }
            }

            let region = BridgeEventFactory.news(from: result, now: Date())
            let event = BridgeEventFactory.newsChangedEvent(
                region: region,
                profile: profile,
                id: BridgeEventFactory.newEventID(),
                timestamp: Date()
            )
            guard
                let data = try? BridgeMessageCoding.encoder().encode(event),
                let json = String(data: data, encoding: .utf8)
            else { continue }
            emit(json)
        }
    }
}
#endif
