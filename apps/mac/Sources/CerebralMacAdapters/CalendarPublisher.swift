// Streaming Schedule events (NIC-126) — the top-left Today panel producer, per relevance profile.
#if canImport(AppKit)
import Foundation
import CerebralCore
import CerebralRuntimeHost

/// Fetches the day's events from a ``CalendarProvider``, resolves each to a mode with the layered
/// ``CalendarRelevanceResolver`` (a `#[mode]` tag → the user's calendar→mode map → the default
/// mode), and emits one `schedule.changed` event **per relevance profile** each tick (NIC-126). The
/// dashboard folds each into its `liveSchedule` map keyed by `calendarProfile`, and the Today panel
/// renders the events for the active mode's profile (surviving mode switches by construction —
/// NIC-131 blueprint generalized to a per-profile map, the same shape News uses).
///
/// Like News, the schedule is per-mode, so this fans out over the distinct profiles the config
/// declares (four). Mirrors ``NewsPublisher``'s battery/visibility discipline on a **slow cadence**
/// (default 10 min — calendar events change on the scale of minutes, not seconds): the loop is
/// deactivated while the dashboard is not visible and reactivation emits immediately. The
/// calendar→mode map is read **per tick**, so a Settings mapping edit takes effect on the next
/// sample without a relaunch; the shell also calls ``refresh()`` on that edit so it is immediate.
///
/// Honest states (never fabricated): a denied Calendar grant → every profile shows "grant access";
/// any other read failure → a generic unavailable; no events for a profile → that profile's honest
/// empty ("Nothing scheduled"). The window runs from now to the end of today, so the panel shows
/// what is left of today and tonight; a multi-day or all-day event overlapping the window is
/// included (the provider's overlap predicate handles that).
public actor CalendarPublisher {
    private let catalog: CalendarProfileCatalog
    private let profiles: [String]
    private let calendarModeMap: @Sendable () -> [String: String]
    private let provider: any CalendarProvider
    private let intervalNanos: UInt64
    private let emit: @Sendable (String) -> Void

    private var loop: Task<Void, Never>?
    private var active = true

    public init(
        catalog: CalendarProfileCatalog,
        calendarModeMap: @escaping @Sendable () -> [String: String],
        provider: any CalendarProvider,
        intervalMs: Int = 600_000,
        emit: @escaping @Sendable (String) -> Void
    ) {
        self.catalog = catalog
        self.profiles = catalog.distinctProfiles
        self.calendarModeMap = calendarModeMap
        self.provider = provider
        self.intervalNanos = UInt64(intervalMs) * 1_000_000
        self.emit = emit
    }

    /// Starts the sampling loop (idempotent). The first tick fires immediately, so the panel
    /// populates (or prompts for the Calendar grant) as soon as the stream starts rather than
    /// after one interval.
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

    /// Emit a fresh sample now, regardless of cadence — used when the user just edited their
    /// calendar→mode mapping (NIC-126), so the panels re-filter at once instead of waiting out the
    /// interval. The mapping is re-read this tick.
    public func refresh() async {
        await tick()
    }

    /// Pause/resume from the shell's visibility signal. Resuming emits a fresh sample immediately
    /// instead of waiting out the current interval.
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
        // Now → end of today (start of tomorrow): the events still to come today and tonight.
        let now = Date()
        let endOfToday = Calendar.current.startOfDay(for: now).addingTimeInterval(24 * 60 * 60)
        let interval = DateInterval(start: now, end: max(endOfToday, now))

        let fetch: Swift.Result<[CalendarEvent], Error>
        do {
            fetch = .success(try await provider.events(within: interval))
        } catch {
            fetch = .failure(error)
        }

        // Read the user's calendar→mode map once and share the resolver across every profile's
        // filter (one settings read, N filters).
        let resolver = CalendarRelevanceResolver(catalog: catalog, calendarModeMap: calendarModeMap())

        for profile in profiles {
            // On success, keep only this profile's events; on failure, every profile degrades to the
            // same honest unavailable (`Result.map` preserves the error).
            let result = fetch.map { resolver.events(forProfile: profile, from: $0) }
            let region = BridgeEventFactory.schedule(from: result)
            let event = BridgeEventFactory.scheduleChangedEvent(
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
