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
/// stored the provider is still asked — a fallback chain may hold a free source needing no
/// credential — and only if nothing can serve does the profile emit an honest "add your API key"
/// state rather than a fabricated list (FR-CFG-03); a provider/network failure emits a generic
/// unavailable. The token is re-read each tick, so adding or replacing the key in Settings takes
/// effect on the next tick without a relaunch.
///
/// ## Quota discipline
///
/// NewsData's free tier is 200 credits/day and this producer spends one request per profile per
/// tick. The expensive part was never the cadence but the **out-of-cadence** ticks: `start()` and
/// every visibility resume fetched immediately, and the dashboard is a backdrop window whose
/// occlusion flips whenever a full-screen app covers it — so a day of ordinary use plus a few
/// rebuild-and-relaunch cycles could exhaust the quota on its own.
///
/// The cadence carries the rest: at 2 h × 4 profiles the scheduled cost is ~48 requests/day. It is
/// not lower because the *page size* rules out the obvious trick — the free tier returns 10
/// articles per request, so merging the profiles into one broad query would leave the narrower
/// profiles with a handful of articles to bucket between them. Four category-filtered requests buy
/// four genuinely relevant profiles for a quarter of the daily quota, which is the better trade.
///
/// Two rules fix that, and they apply to *every* trigger rather than special-casing one:
///
/// - **A minimum fetch interval.** No network fetch happens within `minimumFetchInterval` of the
///   last *attempt* (not the last success — a rate-limited or offline provider must not be
///   hammered either). A blocked tick still emits, from the cache, so launching or un-occluding the
///   dashboard populates the panel instantly and for free. Only ``refresh()`` bypasses the floor:
///   it is the explicit "the user just stored a key" signal.
/// - **A persisted last-good cache.** The cache lives in the operational database, so it survives
///   relaunch: a cold start renders the previous headlines from disk instead of spending a request.
///   A provider failure keeps serving the last good headlines rather than blanking the panel — but
///   only up to `maximumCacheAge` (default 12h, matching the free tier's own article delay), past
///   which the panel degrades to its honest unavailable state. A *missing credential* is never
///   masked by the cache: it always surfaces the "add your key" guidance.
public actor NewsPublisher {
    private let profiles: [String]
    private let secretStore: any SecretStoreManaging
    private let provider: any NewsProvider
    private let reference: String
    private let intervalNanos: UInt64
    private let minimumFetchInterval: TimeInterval
    private let maximumCacheAge: TimeInterval
    private let cacheStore: (any NewsCacheStore)?
    private let now: @Sendable () -> Date
    private let emit: @Sendable (String) -> Void

    private var loop: Task<Void, Never>?
    private var active = true
    private var cache = NewsCacheSnapshot()
    private var hydrated = false

    public init(
        profiles: [String],
        secretStore: any SecretStoreManaging,
        provider: any NewsProvider,
        reference: String = "newsdata_api_key",
        // 2 h. The free tier's articles are 12 h delayed, so a faster cadence cannot return fresher
        // news — it only spends credits. At 2 h × 4 profiles this is ~48 requests/day against a
        // 200/day quota, leaving headroom for relaunches and manual refreshes.
        intervalMs: Int = 7_200_000,
        // Defaults to 90% of the cadence. Deriving it rather than fixing it is deliberate: with an
        // independent constant, lengthening the cadence would silently *raise* the ceiling on spend,
        // because out-of-cadence resume ticks would fetch in the gap. Tied to the interval, the
        // worst case stays a shade over one fetch per cadence however often the dashboard is
        // occluded, relaunched, or resumed.
        minimumFetchIntervalMs: Int? = nil,
        // 12 h: the free tier's own article delay, so nothing served from cache is meaningfully
        // staler than a live fetch would have been. Past it, stale headlines stop being served.
        maximumCacheAgeMs: Int = 43_200_000,
        cacheStore: (any NewsCacheStore)? = nil,
        now: @escaping @Sendable () -> Date = { Date() },
        emit: @escaping @Sendable (String) -> Void
    ) {
        self.profiles = profiles
        self.secretStore = secretStore
        self.provider = provider
        self.reference = reference
        self.intervalNanos = UInt64(intervalMs) * 1_000_000
        self.minimumFetchInterval = TimeInterval(minimumFetchIntervalMs ?? (intervalMs * 9 / 10)) / 1000
        self.maximumCacheAge = TimeInterval(maximumCacheAgeMs) / 1000
        self.cacheStore = cacheStore
        self.now = now
        self.emit = emit
    }

    /// Starts the sampling loop (idempotent). The first tick fires immediately, so the panel
    /// populates as soon as the stream starts rather than after one (long) interval — from the
    /// persisted cache when the last fetch was recent, which is the common case on relaunch.
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
    /// so the panel goes live immediately instead of waiting out the interval. This is the only
    /// path that bypasses the minimum fetch interval: it is an explicit, user-initiated action, not
    /// an ambient lifecycle signal.
    public func refresh() async {
        await tick(force: true)
    }

    /// Re-emit the current cached state without fetching, for a surface that has just become able
    /// to receive events.
    ///
    /// Event delivery is fire-and-forget: the shell drops an event when the webview has not yet
    /// registered its receiver. That was survivable while the first tick always waited on a network
    /// round trip — the page won that race. Serving the first tick from a warm cache made it
    /// instant, so the first `news.changed` now loses the race on a relaunch, and with a 2 h cadence
    /// the panel would sit on its bootstrap "unavailable" until the next scheduled tick. The shell
    /// calls this once the dashboard's bridge handshake proves the page can receive.
    ///
    /// Emits nothing when the cache is empty: on a first-ever run there is no state worth showing,
    /// and emitting an "unavailable" here would only flash it before the first fetch lands.
    public func resend() async {
        hydrateIfNeeded()
        guard !cache.entries.isEmpty else { return }
        emitFromCache(at: now())
    }

    /// Pause/resume from the shell's visibility signal. Resuming emits a fresh sample immediately —
    /// from the cache when the last fetch was recent, so an occlusion flap costs no quota.
    public func setActive(_ nowActive: Bool) async {
        let wasActive = active
        active = nowActive
        if nowActive && !wasActive {
            await tick(force: false)
        }
    }

    private func tickIfActive() async {
        guard active else { return }
        await tick(force: false)
    }

    private func tick(force: Bool) async {
        guard !profiles.isEmpty else { return }
        hydrateIfNeeded()

        let instant = now()
        if force || shouldFetch(at: instant) {
            await fetchAll(at: instant)
        }
        emitFromCache(at: now())
    }

    /// True when no fetch has been attempted yet, or the last attempt is older than the floor.
    /// Measured from the last *attempt* so a failing provider is not retried on every resume.
    private func shouldFetch(at instant: Date) -> Bool {
        guard let last = cache.lastAttemptAt else { return true }
        return instant.timeIntervalSince(last) >= minimumFetchInterval
    }

    /// Loads the persisted cache once per process. A missing or undecodable row is "no cache yet" —
    /// the cache is rebuildable derived state, so a read failure costs one request, never an error.
    private func hydrateIfNeeded() {
        guard !hydrated else { return }
        hydrated = true
        if let stored = try? cacheStore?.load() {
            cache = stored
        }
    }

    /// Reads the token once, fetches every profile, and folds each outcome into the cache. Records
    /// the attempt regardless of outcome, then persists the whole cache in one write.
    private func fetchAll(at instant: Date) async {
        // Read the token once and reuse it across every profile's fetch (one Keychain read).
        let token: Swift.Result<String, Error>
        do {
            token = .success(try await secretStore.readValue(reference: reference))
        } catch {
            token = .failure(error)
        }

        cache.lastAttemptAt = instant

        for profile in profiles {
            let result: Swift.Result<[NewsHeadline], Error>
            switch token {
            case let .failure(tokenError):
                // No usable key. The provider is still asked, because the chain behind it may hold
                // a free source that needs no credential (RSS) — an unconfigured API key must not
                // blank a panel that can be served for free. Only when *nothing* can serve does the
                // key problem surface: a missing keychain entry → guide the user to add the key,
                // any other failure (a denied keychain) → a generic honest unavailable.
                do {
                    result = .success(try await provider.headlines(profile: profile, apiToken: ""))
                } catch {
                    if let native = tokenError as? NativeCapabilityError, case .notFound = native {
                        result = .failure(NewsError.credentialsMissing)
                    } else {
                        result = .failure(tokenError)
                    }
                }
            case let .success(value):
                do {
                    result = .success(try await provider.headlines(profile: profile, apiToken: value))
                } catch {
                    result = .failure(error)
                }
            }
            cache.entries[profile] = merge(result, into: cache.entries[profile], at: instant)
        }

        try? cacheStore?.save(cache)
    }

    /// Folds one profile's fetch outcome into its cached entry.
    ///
    /// A success replaces the entry. A **missing credential** also replaces it — the "add your key"
    /// guidance must never be masked by headlines fetched under an old key. Any other failure keeps
    /// a previously good entry untouched (so a rate-limited or offline tick does not blank the
    /// panel); `fetchedAt` deliberately stays at the original fetch time, which is what lets
    /// ``maximumCacheAge`` eventually retire it.
    private func merge(
        _ result: Swift.Result<[NewsHeadline], Error>, into existing: NewsCacheEntry?, at instant: Date
    ) -> NewsCacheEntry {
        switch result {
        case let .success(headlines):
            return NewsCacheEntry(headlines: headlines, failure: nil, fetchedAt: instant)
        case let .failure(error):
            if (error as? NewsError) == .credentialsMissing {
                return NewsCacheEntry(headlines: [], failure: .credentialsMissing, fetchedAt: instant)
            }
            if let existing, existing.failure == nil {
                return existing
            }
            // Nothing good to fall back on: record *why*, so the panel can say "rate limited,
            // it'll come back" instead of implying something is broken.
            let failure: NewsCacheFailure = (error as? NewsError) == .rateLimited ? .rateLimited : .unavailable
            return NewsCacheEntry(headlines: [], failure: failure, fetchedAt: instant)
        }
    }

    /// Emits one event per profile from the cache — the single emit path, whether this tick fetched
    /// or was blocked by the floor.
    private func emitFromCache(at instant: Date) {
        for profile in profiles {
            let region = BridgeEventFactory.news(from: outcome(for: profile, at: instant), now: instant)
            let event = BridgeEventFactory.newsChangedEvent(
                region: region,
                profile: profile,
                id: BridgeEventFactory.newEventID(),
                timestamp: instant
            )
            guard
                let data = try? BridgeMessageCoding.encoder().encode(event),
                let json = String(data: data, encoding: .utf8)
            else { continue }
            emit(json)
        }
    }

    /// The result to render for one profile. Cached headlines older than ``maximumCacheAge`` are
    /// retired rather than shown as if current — the region carries no staleness marker, so serving
    /// them indefinitely would misrepresent their age. The diagnostic strings here are internal:
    /// the event mapping distinguishes only `credentialsMissing` and never surfaces the text.
    private func outcome(for profile: String, at instant: Date) -> Swift.Result<[NewsHeadline], Error> {
        guard let entry = cache.entries[profile] else {
            return .failure(NewsError.providerFailed("No news has been fetched yet."))
        }
        if let failure = entry.failure {
            switch failure {
            case .credentialsMissing: return .failure(NewsError.credentialsMissing)
            case .rateLimited: return .failure(NewsError.rateLimited)
            case .unavailable: return .failure(NewsError.providerFailed("The last news fetch failed."))
            }
        }
        guard instant.timeIntervalSince(entry.fetchedAt) <= maximumCacheAge else {
            return .failure(NewsError.providerFailed("The cached headlines are too old to show."))
        }
        return .success(entry.headlines)
    }
}
#endif
