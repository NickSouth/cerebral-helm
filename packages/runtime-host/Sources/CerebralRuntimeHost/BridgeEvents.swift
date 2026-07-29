import Foundation
import CerebralContracts
import CerebralCore

/// Encoding for outbound bridge messages (NIC-74b). Matches the generated contracts'
/// ISO-8601 (fractional-seconds) date strategy so message timestamps serialize in the
/// contract format — a plain `JSONEncoder` would emit `Date` as a number.
public enum BridgeMessageCoding {
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            // Formatter is created per call; ISO8601DateFormatter is not Sendable, so
            // the @Sendable strategy closure must capture nothing.
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var container = encoder.singleValueContainer()
            try container.encode(formatter.string(from: date))
        }
        return encoder
    }
}

/// Wraps runtime events as versioned bridge events for delivery to the dashboard
/// (NIC-74b, ADR-004). This increment forwards command-lifecycle transitions; the
/// confirmation/status/config/capability event kinds follow with their producers.
public enum BridgeEventFactory {
    public static func lifecycleEvent(
        _ event: CommandLifecycleEvent, id: String
    ) -> CerebralHelmBridgeEvent {
        CerebralHelmBridgeEvent(
            eventID: id,
            payload: payload(event),
            schemaVersion: "1.0.0",
            timestamp: event.timestamp,
            type: .commandLifecycleTransition
        )
    }

    /// A `confirmation.changed` event: carries the policy-owned disclosure when a
    /// confirmation is pending, or clears it (`confirmation: null`) once resolved. The
    /// dashboard renders the disclosure verbatim and never classifies risk itself.
    public static func confirmationEvent(
        disclosure: CerebralHelmConfirmationDisclosure?, id: String, timestamp: Date
    ) -> CerebralHelmBridgeEvent {
        CerebralHelmBridgeEvent(
            eventID: id,
            payload: confirmationPayload(disclosure),
            schemaVersion: "1.0.0",
            timestamp: timestamp,
            type: .confirmationChanged
        )
    }

    /// A `config.changed` event carrying the target mode's snapshot — the dashboard
    /// folds it over the eager bundle to re-theme and swap regions without remounting
    /// (mode switch, NIC-54/D2). `modes`/`agents` are omitted (a snapshot is the
    /// bootstrap minus the eager bundle).
    public static func configChangedEvent(
        snapshot: CerebralHelmBridgeBootstrapState, id: String, timestamp: Date
    ) -> CerebralHelmBridgeEvent {
        CerebralHelmBridgeEvent(
            eventID: id,
            payload: snapshotPayload(snapshot),
            schemaVersion: "1.0.0",
            timestamp: timestamp,
            type: .configChanged
        )
    }

    /// A `mode.quickapps.changed` event (NIC-149): one mode's quick-app slots were
    /// rewritten through the validated override path. Carries just the changed
    /// widget's state — `config.changed` stays a mode-*switch* event whose snapshot
    /// omits `modes`, so per-widget updates get their own event type (the pattern
    /// for further live-updating mode widgets).
    public static func quickAppsChangedEvent(
        modeId: String, quickApps: [String], id: String, timestamp: Date
    ) -> CerebralHelmBridgeEvent {
        struct Payload: Encodable {
            let modeId: String
            let quickApps: [String]
        }
        return CerebralHelmBridgeEvent(
            eventID: id,
            payload: encodedPayload(Payload(modeId: modeId, quickApps: quickApps)),
            schemaVersion: "1.0.0",
            timestamp: timestamp,
            type: .modeQuickappsChanged
        )
    }

    /// Announces a mode's collapse-all state (NIC-143): `collapsed` is true when the
    /// mode currently holds a hidden "collapsed windows" bucket, so the bottom-bar
    /// collapse/expand control shows the right affordance. Session-only, per-mode
    /// state — emitted on toggle and on every mode switch (the entered mode's state).
    public static func windowCollapseChangedEvent(
        modeId: String, collapsed: Bool, id: String, timestamp: Date
    ) -> CerebralHelmBridgeEvent {
        struct Payload: Encodable {
            let modeId: String
            let collapsed: Bool
        }
        return CerebralHelmBridgeEvent(
            eventID: id,
            payload: encodedPayload(Payload(modeId: modeId, collapsed: collapsed)),
            schemaVersion: "1.0.0",
            timestamp: timestamp,
            type: .modeWindowcollapseChanged
        )
    }

    /// A `widget.data.changed` event (NIC-131 — the widget-liveness blueprint): one
    /// dashboard widget's live data was refreshed by its producer. `widgetId` names the
    /// registered widget slot (e.g. "repositories"); `widget` is the full WidgetData
    /// envelope the dashboard renders. The reducer keys it into a runtime `liveWidgets`
    /// map by `widgetId`, so a rail resolves its slot as the live value over the bootstrap
    /// value — and it survives mode switches because it lives outside `regions` (which a
    /// mode-switch snapshot swaps wholesale). Generic over the widget payload so each
    /// widget's producer passes its own encoded envelope with no shared concrete type here.
    public static func widgetDataChangedEvent<Widget: Encodable>(
        widgetId: String, widget: Widget, id: String, timestamp: Date
    ) -> CerebralHelmBridgeEvent {
        return CerebralHelmBridgeEvent(
            eventID: id,
            payload: encodedPayload(WidgetDataChangedPayload(widgetId: widgetId, widget: widget)),
            schemaVersion: "1.0.0",
            timestamp: timestamp,
            type: .widgetDataChanged
        )
    }

    /// `{ widgetId, widget }` — the `widget.data.changed` payload (NIC-131). Declared at
    /// enum scope (Swift forbids a type nested inside a generic function) and generic over
    /// the widget envelope so each producer supplies its own encoded shape.
    private struct WidgetDataChangedPayload<Widget: Encodable>: Encodable {
        let widgetId: String
        let widget: Widget
    }

    // MARK: - Repositories widget (NIC-131)

    /// The `repositories` widget's live envelope — the Swift mirror of the web `WidgetData`
    /// for this widget. Optional fields are omitted (not encoded as null) when nil by the
    /// synthesized encoding, matching the envelope the dashboard renders.
    public struct RepositoriesWidget: Encodable, Sendable {
        public let widgetId: String
        public let state: String
        public let headline: String?
        public let emptyMessage: String?
        public let freshness: WidgetFreshnessPayload?
        public let data: RepositoriesWidgetData?
    }

    public struct RepositoriesWidgetData: Encodable, Sendable {
        public let items: [RepositoryItem]
    }

    /// One repository row. `branch` is omitted when the repo's HEAD couldn't be resolved
    /// (never fabricated); `path` is the click-to-open target (`project.open`, Increment 4).
    public struct RepositoryItem: Encodable, Sendable {
        public let id: String
        public let name: String
        public let branch: String?
        public let path: String
    }

    /// Freshness stamp mirroring the web `WidgetFreshness` (`observedAt` + human label).
    public struct WidgetFreshnessPayload: Encodable, Sendable {
        public let observedAt: Date
        public let label: String
    }

    /// Maps the active-repos reader's result into the `repositories` widget envelope
    /// (NIC-131). A read failure is an honest `unavailable`; a readable-but-empty root is
    /// `empty`; otherwise `ready` with one row per repo. Nothing is fabricated — a repo
    /// whose branch couldn't be resolved simply omits it.
    public static func repositoriesWidget(
        from result: Swift.Result<[RepoStatus], Error>, now: Date
    ) -> RepositoriesWidget {
        switch result {
        case .failure:
            return RepositoriesWidget(
                widgetId: "repositories", state: "unavailable", headline: nil,
                emptyMessage: "Your projects folder isn't available.", freshness: nil, data: nil
            )
        case let .success(repos) where repos.isEmpty:
            return RepositoriesWidget(
                widgetId: "repositories", state: "empty", headline: nil,
                emptyMessage: "No repositories in your projects folder yet.", freshness: nil, data: nil
            )
        case let .success(repos):
            let items = repos.map {
                RepositoryItem(id: $0.id, name: $0.name, branch: $0.branch, path: $0.path)
            }
            return RepositoriesWidget(
                widgetId: "repositories", state: "ready",
                headline: repos.count == 1 ? "1 repository" : "\(repos.count) repositories",
                emptyMessage: nil,
                freshness: WidgetFreshnessPayload(observedAt: now, label: "just now"),
                data: RepositoriesWidgetData(items: items)
            )
        }
    }

    // MARK: - Canvas School widgets (NIC-132)

    /// The `courses` widget's live envelope (NIC-132, School right slot) — the Swift mirror of the
    /// web `WidgetData` for this widget. Optional fields are omitted (not encoded as null) when nil.
    public struct CanvasCoursesWidget: Encodable, Sendable {
        public let widgetId: String
        public let state: String
        public let headline: String?
        public let emptyMessage: String?
        public let freshness: WidgetFreshnessPayload?
        public let data: CanvasCoursesWidgetData?
    }

    public struct CanvasCoursesWidgetData: Encodable, Sendable {
        public let items: [CanvasCourseItem]
    }

    /// One course row. `percent`/`letterGrade` are omitted when Canvas has none — and are omitted
    /// entirely for a hidden grade, so a score the user hid in Canvas never crosses the bridge.
    public struct CanvasCourseItem: Encodable, Sendable {
        public let id: String
        public let name: String
        public let code: String?
        public let percent: Double?
        public let letterGrade: String?
        public let gradeHidden: Bool?
        public let url: String?
    }

    /// The `deadlines` widget's live envelope (NIC-132, School left slot).
    public struct CanvasDeadlinesWidget: Encodable, Sendable {
        public let widgetId: String
        public let state: String
        public let headline: String?
        public let emptyMessage: String?
        public let freshness: WidgetFreshnessPayload?
        public let data: CanvasDeadlinesWidgetData?
    }

    public struct CanvasDeadlinesWidgetData: Encodable, Sendable {
        public let items: [CanvasDeadlineItem]
    }

    /// One upcoming assignment row. `dueAt` (local wall-clock ISO) is omitted when the assignment is
    /// undated; `courseName`/`url` are omitted when unknown.
    public struct CanvasDeadlineItem: Encodable, Sendable {
        public let id: String
        public let title: String
        public let dueAt: String?
        public let courseName: String?
        public let url: String?
    }

    /// Maps the latest Canvas scrape into the `courses` widget envelope (NIC-132). A read failure or
    /// a never-scraped store is an honest `unavailable` (connect the extension); a scrape with no
    /// courses is `empty`; otherwise `ready` — or `stale`, still showing the courses with a data-age
    /// label, when the scrape is older than `staleAfter`. A hidden grade never fabricates a score and
    /// its percent/letter never cross the bridge.
    public static func canvasCoursesWidget(
        from result: Swift.Result<CanvasScrapeSnapshot?, Error>, now: Date, staleAfter: TimeInterval,
        hiddenIds: Set<String> = []
    ) -> CanvasCoursesWidget {
        switch canvasResolution(from: result, now: now, staleAfter: staleAfter) {
        case .unavailable:
            return CanvasCoursesWidget(
                widgetId: "courses", state: "unavailable", headline: nil,
                emptyMessage: "Open Canvas in Chrome to sync your courses.", freshness: nil, data: nil
            )
        case let .ready(snapshot, state, freshness):
            // Drop courses the user has manually hidden (NIC-132) — if that leaves none, the widget is
            // an honest empty state, not a missing capability.
            let visible = snapshot.courses.filter { !hiddenIds.contains($0.id) }
            guard !visible.isEmpty else {
                return CanvasCoursesWidget(
                    widgetId: "courses", state: "empty", headline: nil,
                    emptyMessage: "No current courses — open Canvas in Chrome to sync.", freshness: nil, data: nil
                )
            }
            let items = visible.map { course -> CanvasCourseItem in
                let hidden = course.gradeHidden
                return CanvasCourseItem(
                    id: course.id, name: course.name, code: course.code,
                    percent: hidden ? nil : course.percent,
                    letterGrade: hidden ? nil : course.letterGrade,
                    gradeHidden: hidden ? true : nil,
                    url: course.url
                )
            }
            return CanvasCoursesWidget(
                widgetId: "courses", state: state,
                headline: visible.count == 1 ? "1 course" : "\(visible.count) courses",
                emptyMessage: nil, freshness: freshness,
                data: CanvasCoursesWidgetData(items: items)
            )
        }
    }

    /// Maps the latest Canvas scrape into the `deadlines` widget envelope (NIC-132). Assignments are
    /// sorted soonest-first (undated last); the scrape has already excluded submitted/completed work.
    /// Failure/never-scraped → `unavailable`; no upcoming work → `empty`; otherwise `ready`/`stale`
    /// with a data-age label.
    public static func canvasDeadlinesWidget(
        from result: Swift.Result<CanvasScrapeSnapshot?, Error>, now: Date, staleAfter: TimeInterval,
        hiddenIds: Set<String> = []
    ) -> CanvasDeadlinesWidget {
        switch canvasResolution(from: result, now: now, staleAfter: staleAfter) {
        case .unavailable:
            return CanvasDeadlinesWidget(
                widgetId: "deadlines", state: "unavailable", headline: nil,
                emptyMessage: "Open Canvas in Chrome to sync your deadlines.", freshness: nil, data: nil
            )
        case let .ready(snapshot, state, freshness):
            // Drop assignments the user has manually hidden (NIC-132); none left → honest empty.
            let sorted = snapshot.deadlines
                .filter { !hiddenIds.contains($0.id) }
                .sorted(by: canvasDeadlineOrder)
            guard !sorted.isEmpty else {
                return CanvasDeadlinesWidget(
                    widgetId: "deadlines", state: "empty", headline: nil,
                    emptyMessage: "Nothing due soon.", freshness: nil, data: nil
                )
            }
            let items = sorted.map {
                CanvasDeadlineItem(
                    id: $0.id, title: $0.title, dueAt: $0.dueAt, courseName: $0.courseName, url: $0.url
                )
            }
            return CanvasDeadlinesWidget(
                widgetId: "deadlines", state: state,
                headline: sorted.count == 1 ? "1 due soon" : "\(sorted.count) due soon",
                emptyMessage: nil, freshness: freshness,
                data: CanvasDeadlinesWidgetData(items: items)
            )
        }
    }

    // MARK: Canvas mapping helpers

    /// The shared resolution of a Canvas scrape result into a widget state, independent of which
    /// widget renders it: a failure or a never-scraped store is `unavailable`; otherwise the
    /// snapshot is `ready`, tagged `stale` when older than `staleAfter`, carrying its data-age stamp.
    private enum CanvasResolution {
        case unavailable
        case ready(CanvasScrapeSnapshot, state: String, freshness: WidgetFreshnessPayload)
    }

    private static func canvasResolution(
        from result: Swift.Result<CanvasScrapeSnapshot?, Error>, now: Date, staleAfter: TimeInterval
    ) -> CanvasResolution {
        switch result {
        case .failure:
            return .unavailable
        case .success(nil):
            return .unavailable
        case let .success(snapshot?):
            let age = now.timeIntervalSince(snapshot.scrapedAt)
            let state = age > staleAfter ? "stale" : "ready"
            let freshness = WidgetFreshnessPayload(observedAt: snapshot.scrapedAt, label: canvasAgeLabel(age))
            return .ready(snapshot, state: state, freshness: freshness)
        }
    }

    /// Sort order for upcoming assignments: soonest `dueAt` first, undated last, `id` as a stable
    /// tiebreak. `dueAt` is a fixed-format local ISO string, so a lexicographic compare is
    /// chronological.
    private static func canvasDeadlineOrder(_ a: CanvasDeadline, _ b: CanvasDeadline) -> Bool {
        switch (a.dueAt, b.dueAt) {
        case let (x?, y?): return x == y ? a.id < b.id : x < y
        case (nil, _?): return false // an undated assignment sorts after any dated one
        case (_?, nil): return true
        case (nil, nil): return a.id < b.id
        }
    }

    /// A coarse "data age" label from an interval: "just now" (<1m), "Nm ago" (<1h), "Nh ago" (<1d),
    /// else "Nd ago". Deterministic — derived from the injected `now` and the scrape time.
    private static func canvasAgeLabel(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval))
        if seconds < 60 { return "just now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        return "\(hours / 24)d ago"
    }

    // MARK: - Weather (NIC-169)

    /// A `weather.changed` event carrying the bottom bar's ambient weather channel (NIC-169).
    /// The dashboard folds `payload.weather` into its runtime-only `liveWeather` field, which
    /// wins over the per-mode bootstrap `weather` and survives mode switches by construction
    /// (it lives outside the mode snapshot). Weather is machine-global, so one live value is
    /// correct across every mode. Emitted by the ``WeatherPublisher`` (Increment 5).
    public static func weatherChangedEvent(
        channel: DashboardWeatherChannel, id: String, timestamp: Date
    ) -> CerebralHelmBridgeEvent {
        struct Payload: Encodable {
            let weather: DashboardWeatherChannel
        }
        return CerebralHelmBridgeEvent(
            eventID: id,
            payload: encodedPayload(Payload(weather: channel)),
            schemaVersion: "1.0.0",
            timestamp: timestamp,
            type: .weatherChanged
        )
    }

    /// Maps a weather-provider result into the bottom bar's `DashboardWeatherChannel` (NIC-169).
    /// A reading is `ready` with a rounded "NN°F · Condition" label; a failure is an honest
    /// `unavailable` with no fabricated temperature or condition — a missing/denied location
    /// reads "Location unavailable", any other failure "Weather unavailable" (FR-SAF-07).
    public static func weather(
        from result: Swift.Result<WeatherReading, Error>, now _: Date
    ) -> DashboardWeatherChannel {
        switch result {
        case let .success(reading):
            let rounded = Int(reading.temperatureF.rounded())
            return DashboardWeatherChannel(
                condition: reading.condition,
                label: "\(rounded)°F · \(reading.condition)",
                state: .ready,
                temperatureF: Double(rounded)
            )
        case let .failure(error):
            let isLocation = (error as? WeatherError).map { $0 == .locationUnavailable } ?? false
            return DashboardWeatherChannel(
                condition: nil,
                label: isLocation ? "Location unavailable" : "Weather unavailable",
                state: .unavailable,
                temperatureF: nil
            )
        }
    }

    // MARK: - News (NIC-127)

    /// A `news.changed` event carrying one relevance profile's headlines (NIC-127). The dashboard
    /// folds `payload.news` into its runtime-only `liveNews` map keyed by `payload.profile`; the
    /// News panel resolves `liveNews[activeMode.newsProfile]` over the per-mode bootstrap
    /// `regions.news` (live wins) and it survives mode switches by construction (the map lives
    /// outside the mode snapshot). Unlike weather, news content differs per mode, so the event
    /// carries the profile it is for. Emitted per distinct profile by the ``NewsPublisher``
    /// (Increment 7).
    public static func newsChangedEvent(
        region: DashboardNewsRegion, profile: String, id: String, timestamp: Date
    ) -> CerebralHelmBridgeEvent {
        struct Payload: Encodable {
            let profile: String
            let news: DashboardNewsRegion
        }
        return CerebralHelmBridgeEvent(
            eventID: id,
            payload: encodedPayload(Payload(profile: profile, news: region)),
            schemaVersion: "1.0.0",
            timestamp: timestamp,
            type: .newsChanged
        )
    }

    /// Maps a news-provider result into the `DashboardNewsRegion` for the News panel (NIC-127). A
    /// missing credential is an honest `unavailable` that guides the user to add their key; any
    /// other failure is a generic `unavailable` (the raw diagnostic is never surfaced); an empty
    /// result is `empty`; otherwise `ready` with at most four headlines (design spec §5.4 says
    /// three; the owner raised it to four so the left-rail panel fills without dead space).
    /// Nothing is fabricated — a headline without a link simply omits its `url`.
    public static func news(
        from result: Swift.Result<[NewsHeadline], Error>, now _: Date
    ) -> DashboardNewsRegion {
        switch result {
        case let .failure(error):
            let credentialsMissing = (error as? NewsError).map { $0 == .credentialsMissing } ?? false
            return DashboardNewsRegion(
                emptyMessage: credentialsMissing
                    ? "Add your NewsData API key in Settings → Setup to see news."
                    : "News isn't available right now.",
                headlines: [],
                state: .unavailable
            )
        case let .success(headlines) where headlines.isEmpty:
            return DashboardNewsRegion(
                emptyMessage: "No headlines right now.", headlines: [], state: .empty
            )
        case let .success(headlines):
            // Up to four headlines (owner-raised from the spec's three) — cap, never pad. `url` is
            // the article's navigable destination (opened via web.open); nil is omitted, never
            // fabricated.
            let items = headlines.prefix(4).map {
                DashboardNewsHeadline(id: $0.id, source: $0.source, title: $0.title, url: $0.url)
            }
            return DashboardNewsRegion(emptyMessage: nil, headlines: items, state: .ready)
        }
    }

    // MARK: - Schedule / Calendar (NIC-126)

    /// A `schedule.changed` event carrying one relevance profile's events (NIC-126). The dashboard
    /// folds `payload.schedule` into its runtime-only `liveSchedule` map keyed by `payload.profile`;
    /// the Today panel resolves `liveSchedule[activeMode.calendarProfile]` over the per-mode bootstrap
    /// `regions.schedule` (live wins) and it survives mode switches by construction (the map lives
    /// outside the mode snapshot). Like news, calendar relevance differs per mode, so the event
    /// carries the profile it is for. Emitted per distinct profile by the `CalendarPublisher`
    /// (Increment 5).
    public static func scheduleChangedEvent(
        region: DashboardScheduleRegion, profile: String, id: String, timestamp: Date
    ) -> CerebralHelmBridgeEvent {
        struct Payload: Encodable {
            let profile: String
            let schedule: DashboardScheduleRegion
        }
        return CerebralHelmBridgeEvent(
            eventID: id,
            payload: encodedPayload(Payload(profile: profile, schedule: region)),
            schemaVersion: "1.0.0",
            timestamp: timestamp,
            type: .scheduleChanged
        )
    }

    /// Maps a calendar-provider result into the `DashboardScheduleRegion` for the Today panel
    /// (NIC-126). A denied permission is an honest `unavailable` that guides the user to grant
    /// Calendar access; any other failure is a generic `unavailable` (the raw diagnostic is never
    /// surfaced); an empty result is `empty`; otherwise `ready` with the earliest four events
    /// (the panel reserves four rows). Nothing is fabricated.
    ///
    /// Events are ordered by start ascending before the cap so the panel shows the next four. Each
    /// item's `kind` is `tonight` for a timed event starting at or after 18:00 local, else `today`;
    /// an all-day event is always `today` (owner rule) and carries no time. `start` is a local
    /// wall-clock `yyyy-MM-ddTHH:mm:ss` string so the panel's naive `HH:mm` slice reads the event's
    /// local time; `calendar` is injectable so the mapping is deterministic in tests.
    public static func schedule(
        from result: Swift.Result<[CalendarEvent], Error>, calendar: Calendar = .current
    ) -> DashboardScheduleRegion {
        switch result {
        case let .failure(error):
            let denied = (error as? CalendarError).map { $0 == .permissionDenied } ?? false
            return DashboardScheduleRegion(
                emptyMessage: denied
                    ? "Grant Calendar access in Settings → Setup to see your schedule."
                    : "Your schedule isn't available right now.",
                items: [],
                state: .unavailable
            )
        case let .success(events) where events.isEmpty:
            return DashboardScheduleRegion(
                emptyMessage: "Nothing scheduled.", items: [], state: .empty
            )
        case let .success(events):
            let items = events
                .sorted { $0.start < $1.start }
                .prefix(4)
                .map { event in
                    DashboardScheduleItem(
                        id: event.id,
                        kind: scheduleKind(for: event, calendar: calendar),
                        location: event.location,
                        start: event.isAllDay ? nil : localClockString(for: event.start, calendar: calendar),
                        title: event.title
                    )
                }
            return DashboardScheduleRegion(emptyMessage: nil, items: Array(items), state: .ready)
        }
    }

    /// `tonight` for a timed event at or after 18:00 local, else `today`; an all-day event is always
    /// `today` (owner rule — it has no meaningful hour).
    private static func scheduleKind(for event: CalendarEvent, calendar: Calendar) -> DashboardScheduleKind {
        if event.isAllDay {
            return .today
        }
        let hour = calendar.component(.hour, from: event.start)
        return hour >= 18 ? .tonight : .today
    }

    /// A `yyyy-MM-ddTHH:mm:ss` string of the instant's local wall-clock components, so the panel's
    /// naive `slice(11, 16)` reads the event's local time (the panel does not convert time zones).
    private static func localClockString(for date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return String(
            format: "%04d-%02d-%02dT%02d:%02d:00",
            c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0
        )
    }

    // MARK: - Projects widget (NIC-129)

    /// The `projects` widget's live envelope — the Swift mirror of the web `WidgetData` for
    /// this widget. Optional fields are omitted (not encoded as null) when nil by the
    /// synthesized encoding, matching the envelope the dashboard renders.
    public struct ProjectsWidget: Encodable, Sendable {
        public let widgetId: String
        public let state: String
        public let headline: String?
        public let emptyMessage: String?
        public let freshness: WidgetFreshnessPayload?
        public let data: ProjectsWidgetData?
    }

    public struct ProjectsWidgetData: Encodable, Sendable {
        public let items: [ProjectItem]
    }

    /// One project row, in most-important-first order (the reader already sorted them).
    /// `descriptorPath` is omitted when the project has no `PROJECT.md`; `hasDescriptor` is
    /// the honest gate the dashboard uses to enable/disable the click-to-expand row (Inc 6).
    public struct ProjectItem: Encodable, Sendable {
        public let id: String
        public let name: String
        public let path: String
        public let descriptorPath: String?
        public let hasDescriptor: Bool
    }

    /// Maps the active-projects reader's result into the `projects` widget envelope (NIC-129).
    /// A read failure is an honest `unavailable`; a readable-but-empty root is `empty`;
    /// otherwise `ready` with one row per project. Nothing is fabricated — a project without a
    /// `PROJECT.md` simply reports `hasDescriptor == false` and omits its descriptor path.
    public static func projectsWidget(
        from result: Swift.Result<[ProjectSummary], Error>, now: Date
    ) -> ProjectsWidget {
        switch result {
        case .failure:
            return ProjectsWidget(
                widgetId: "projects", state: "unavailable", headline: nil,
                emptyMessage: "Your projects folder isn't available.", freshness: nil, data: nil
            )
        case let .success(projects) where projects.isEmpty:
            return ProjectsWidget(
                widgetId: "projects", state: "empty", headline: nil,
                emptyMessage: "No projects in your projects folder yet.", freshness: nil, data: nil
            )
        case let .success(projects):
            let items = projects.map {
                ProjectItem(
                    id: $0.id, name: $0.name, path: $0.path,
                    descriptorPath: $0.descriptorPath, hasDescriptor: $0.hasDescriptor
                )
            }
            return ProjectsWidget(
                widgetId: "projects", state: "ready",
                headline: projects.count == 1 ? "1 project" : "\(projects.count) projects",
                emptyMessage: nil,
                freshness: WidgetFreshnessPayload(observedAt: now, label: "just now"),
                data: ProjectsWidgetData(items: items)
            )
        }
    }

    // MARK: - Releases widget (NIC-134)

    /// The `releases` widget's live envelope — the Swift mirror of the web `WidgetData` for the
    /// Entertainment right slot (NIC-134). Optional fields are omitted (not encoded as null)
    /// when nil by the synthesized encoding, matching the envelope the dashboard renders.
    public struct ReleasesWidget: Encodable, Sendable {
        public let widgetId: String
        public let state: String
        public let headline: String?
        public let emptyMessage: String?
        public let freshness: WidgetFreshnessPayload?
        public let data: ReleasesWidgetData?
    }

    public struct ReleasesWidgetData: Encodable, Sendable {
        public let items: [ReleaseWidgetItem]
    }

    /// One release row. `mediaType` is the ``ReleaseMediaType`` raw value (`"movie" | "tv"`),
    /// matching the web `ReleaseWidgetItem`; `year` is omitted when the provider had no release
    /// date (never fabricated).
    public struct ReleaseWidgetItem: Encodable, Sendable {
        public let id: String
        public let title: String
        public let mediaType: String
        public let year: Int?
        /// Poster artwork as a self-contained `data:` URI, omitted when absent (never null).
        public let posterImage: String?
    }

    /// Maps a releases-provider result into the `releases` widget envelope (NIC-134). A missing
    /// credential is an honest `unavailable` that guides the user to add their key; any other
    /// failure is a generic `unavailable`; an empty result is `empty`; otherwise `ready` with one
    /// row per release. Nothing is fabricated — an item without a known year simply omits it. The
    /// headline is the widget's identity ("New & hot") rather than a count, since the list is a
    /// rotating hot/new selection, not a set the user is tracking.
    public static func releasesWidget(
        from result: Swift.Result<[ReleaseItem], Error>, now: Date
    ) -> ReleasesWidget {
        switch result {
        case let .failure(error):
            let credentialsMissing = (error as? ReleaseError).map { $0 == .credentialsMissing } ?? false
            return ReleasesWidget(
                widgetId: "releases", state: "unavailable", headline: nil,
                emptyMessage: credentialsMissing
                    ? "Add your TMDB API key in Settings → Setup to see new releases."
                    : "Releases aren't available right now.",
                freshness: nil, data: nil
            )
        case let .success(releases) where releases.isEmpty:
            return ReleasesWidget(
                widgetId: "releases", state: "empty", headline: nil,
                emptyMessage: "No new releases right now.", freshness: nil, data: nil
            )
        case let .success(releases):
            let items = releases.map {
                ReleaseWidgetItem(
                    id: $0.id, title: $0.title, mediaType: $0.mediaType.rawValue,
                    year: $0.year, posterImage: $0.posterImage
                )
            }
            return ReleasesWidget(
                widgetId: "releases", state: "ready", headline: "New & hot", emptyMessage: nil,
                freshness: WidgetFreshnessPayload(observedAt: now, label: "just now"),
                data: ReleasesWidgetData(items: items)
            )
        }
    }

    // MARK: - Spotify widget (NIC-133)

    /// The `spotify` widget's live envelope — the Swift mirror of the web `WidgetData` for the
    /// Entertainment left slot (NIC-133). Optional fields are omitted (not encoded as null) when
    /// nil by the synthesized encoding, matching the envelope the dashboard renders.
    public struct SpotifyWidget: Encodable, Sendable {
        public let widgetId: String
        public let state: String
        public let headline: String?
        public let emptyMessage: String?
        public let freshness: WidgetFreshnessPayload?
        public let data: SpotifyWidgetData?
    }

    /// The now-playing track (a flat payload — a `ready` widget always carries a track). `album`
    /// and `artworkImage` are omitted when Spotify had none (never fabricated); `artworkImage` is a
    /// self-contained `data:` URI. Matches the web `SpotifyWidgetPayload`.
    public struct SpotifyWidgetData: Encodable, Sendable {
        // The now-playing fields are optional so the idle "recently played" state can reuse this
        // envelope with just `recent` populated (no current track).
        public let track: String?
        public let artist: String?
        public let album: String?
        public let artworkImage: String?
        public let isPlaying: Bool?
        public let deviceName: String?
        public let progressMs: Int?
        public let durationMs: Int?
        public let upNextTrack: String?
        public let upNextArtist: String?
        /// The recently-played list, populated only in the idle state (no current track).
        public let recent: [SpotifyRecentTrackPayload]?
    }

    public struct SpotifyRecentTrackPayload: Encodable, Sendable {
        public let track: String
        public let artist: String
    }

    /// Maps a now-playing result into the `spotify` widget envelope (NIC-133). The states are
    /// worded honestly: a missing credential guides the user to connect; a rejected authorization
    /// guides them to reconnect; any other failure is a generic `unavailable` that never leaks the
    /// diagnostic; nothing playing (a successful `nil`) is a healthy `empty`; otherwise `ready`
    /// with the current track. Nothing is fabricated — a track without an album/artwork omits it.
    public static func spotifyWidget(
        from result: Swift.Result<SpotifyNowPlaying?, Error>,
        recent: [SpotifyRecentTrack] = [],
        now: Date
    ) -> SpotifyWidget {
        switch result {
        case let .failure(error):
            let message: String
            switch error as? SpotifyPlaybackError {
            case .credentialsMissing:
                message = "Connect Spotify in Settings → Setup to see what's playing."
            case .notConnected:
                message = "Reconnect Spotify in Settings → Setup."
            default:
                message = "Spotify isn't available right now."
            }
            return SpotifyWidget(
                widgetId: "spotify", state: "unavailable", headline: nil,
                emptyMessage: message, freshness: nil, data: nil
            )
        case .success(.none):
            // Nothing playing: offer the recently-played "jump back in" list when we have one,
            // otherwise a plain empty state.
            guard !recent.isEmpty else {
                return SpotifyWidget(
                    widgetId: "spotify", state: "empty", headline: nil,
                    emptyMessage: "Nothing playing right now.", freshness: nil, data: nil
                )
            }
            return SpotifyWidget(
                widgetId: "spotify", state: "ready", headline: "Recently played", emptyMessage: nil,
                freshness: nil,
                data: SpotifyWidgetData(
                    track: nil, artist: nil, album: nil, artworkImage: nil, isPlaying: nil,
                    deviceName: nil, progressMs: nil, durationMs: nil, upNextTrack: nil, upNextArtist: nil,
                    recent: recent.map { SpotifyRecentTrackPayload(track: $0.track, artist: $0.artist) }
                )
            )
        case let .success(.some(track)):
            // No freshness label: the widget polls on a fast cadence and is essentially always
            // live, so a "just now" stamp is noise (owner) — omitting it also reclaims a line.
            return SpotifyWidget(
                widgetId: "spotify", state: "ready", headline: "Now playing", emptyMessage: nil,
                freshness: nil,
                data: SpotifyWidgetData(
                    track: track.track, artist: track.artist, album: track.album,
                    artworkImage: track.artworkImage, isPlaying: track.isPlaying,
                    deviceName: track.deviceName, progressMs: track.progressMs, durationMs: track.durationMs,
                    upNextTrack: track.upNextTrack, upNextArtist: track.upNextArtist, recent: nil
                )
            )
        }
    }

    // MARK: - Stocks widget (NIC-128)

    /// The `stocks` widget's live envelope — the Swift mirror of the web `WidgetData` for the
    /// Executive left slot (NIC-128). Optional fields are omitted (not encoded as null) when nil,
    /// matching the envelope the dashboard renders.
    public struct StocksWidget: Encodable, Sendable {
        public let widgetId: String
        public let state: String
        public let headline: String?
        public let emptyMessage: String?
        public let freshness: WidgetFreshnessPayload?
        public let data: StocksWidgetData?
    }

    public struct StocksWidgetData: Encodable, Sendable {
        public let items: [StockQuoteWidgetItem]
    }

    /// One ticker row. `symbol` is always present; `price`/`change`/`changePercent` are omitted
    /// (never fabricated) when the symbol couldn't be resolved, so the web tile shows a muted "—".
    public struct StockQuoteWidgetItem: Encodable, Sendable {
        public let symbol: String
        public let price: Double?
        public let change: Double?
        public let changePercent: Double?
        /// Recent daily closes (oldest → newest) for the tile sparkline, omitted (not null) when
        /// no history was resolved — the tile then shows no line.
        public let history: [Double]?
    }

    /// Maps a batch of per-symbol quote results into the `stocks` widget envelope (NIC-128). A
    /// whole-widget failure degrades honestly: a missing credential guides the user to add their
    /// Finnhub key; any other failure is a generic `unavailable`. An empty batch (no tickers
    /// configured) is `empty`. A batch where *every* symbol failed is also `unavailable` — a grid
    /// of dashes under "ready" would misrepresent a total outage. Otherwise `ready` with one row
    /// per ticker, each carrying its figures or omitting them for an unresolved symbol. The
    /// headline is a plain count ("N tickers"), never a fabricated market-sentiment phrase.
    public static func stocksWidget(
        from result: Swift.Result<[StockQuoteResult], Error>, now: Date
    ) -> StocksWidget {
        switch result {
        case let .failure(error):
            let credentialsMissing = (error as? StockQuoteError).map { $0 == .credentialsMissing } ?? false
            return StocksWidget(
                widgetId: "stocks", state: "unavailable", headline: nil,
                emptyMessage: credentialsMissing
                    ? "Add your Finnhub API key in Settings → Setup to track stocks."
                    : "Stocks aren't available right now.",
                freshness: nil, data: nil
            )
        case let .success(rows) where rows.isEmpty:
            return StocksWidget(
                widgetId: "stocks", state: "empty", headline: nil,
                emptyMessage: "Add tickers in Settings → Setup to track them here.",
                freshness: nil, data: nil
            )
        case let .success(rows) where rows.allSatisfy({ $0.quote == nil }):
            return StocksWidget(
                widgetId: "stocks", state: "unavailable", headline: nil,
                emptyMessage: "Stocks aren't available right now.", freshness: nil, data: nil
            )
        case let .success(rows):
            let items = rows.map { row in
                StockQuoteWidgetItem(
                    symbol: row.symbol,
                    price: row.quote?.price,
                    change: row.quote?.change,
                    changePercent: row.quote?.changePercent,
                    // A sparkline needs at least two points to draw a line; anything shorter is
                    // dropped so the tile omits the line rather than rendering a degenerate one.
                    history: (row.history?.count ?? 0) >= 2 ? row.history : nil
                )
            }
            return StocksWidget(
                widgetId: "stocks", state: "ready",
                headline: rows.count == 1 ? "1 ticker" : "\(rows.count) tickers",
                emptyMessage: nil,
                freshness: WidgetFreshnessPayload(observedAt: now, label: "just now"),
                data: StocksWidgetData(items: items)
            )
        }
    }

    // MARK: - Project Git Status widget (NIC-130)

    /// The per-repo inputs the Project Git Status producer assembles for one repository (NIC-130):
    /// the local `branch`/`sync` (always available, from ``GitSyncReader``), the resolved GitHub
    /// `remote` (nil when `origin` isn't GitHub), and the GitHub `github` result (nil when there is
    /// no remote; a `.failure` when a remote exists but the fetch or credential failed). Not
    /// `Sendable` — it is built and consumed synchronously by the producer, and `github` carries a
    /// non-Sendable `Error`.
    public struct ProjectGitStatusInput {
        public let id: String
        public let name: String
        public let branch: String?
        public let sync: GitSyncState?
        public let remote: GitRemote?
        public let github: Swift.Result<GitHubRepoReport, Error>?

        public init(
            id: String, name: String, branch: String?, sync: GitSyncState?,
            remote: GitRemote?, github: Swift.Result<GitHubRepoReport, Error>?
        ) {
            self.id = id
            self.name = name
            self.branch = branch
            self.sync = sync
            self.remote = remote
            self.github = github
        }
    }

    /// The `project-git-status` widget's live envelope — the Swift mirror of the web `WidgetData`
    /// for the Developer left slot (NIC-130). Optional fields are omitted (not encoded as null)
    /// when nil by the synthesized encoding, matching the envelope the dashboard renders.
    public struct ProjectGitStatusWidget: Encodable, Sendable {
        public let widgetId: String
        public let state: String
        public let headline: String?
        public let emptyMessage: String?
        public let freshness: WidgetFreshnessPayload?
        public let data: ProjectGitStatusWidgetData?
    }

    public struct ProjectGitStatusWidgetData: Encodable, Sendable {
        public let repositories: [ProjectGitStatusItemPayload]
    }

    /// One repository's report. `branch`/`sync` are the local state (omitted when unresolved);
    /// `remote` is the GitHub `owner/repo` (omitted when `origin` isn't GitHub — the web then shows
    /// "Not a GitHub repository"); `github` carries the read-only GitHub report or an honest
    /// unavailable/rate-limited sub-state (omitted when there is no remote).
    public struct ProjectGitStatusItemPayload: Encodable, Sendable {
        public let id: String
        public let name: String
        public let branch: String?
        public let sync: String?
        public let remote: GitHubRemotePayload?
        public let github: ProjectGitHubReportPayload?
    }

    public struct GitHubRemotePayload: Encodable, Sendable {
        public let owner: String
        public let repo: String
    }

    /// The GitHub half of a repo's report. When `state` is `ready` the PR/checks/commit fields are
    /// populated; otherwise `message` carries the honest unavailable/rate-limited text and the rest
    /// are omitted. `checks.state` may be `none` (no CI) — a first-class tidy state the web renders
    /// by omitting the CI line, distinct from the section being unavailable.
    public struct ProjectGitHubReportPayload: Encodable, Sendable {
        public let state: String
        public let openPullRequests: OpenPullRequestsPayload?
        public let checks: ChecksPayload?
        public let recentCommits: [CommitPayload]?
        public let message: String?
    }

    public struct OpenPullRequestsPayload: Encodable, Sendable {
        public let count: Int
        public let titles: [String]
    }

    public struct ChecksPayload: Encodable, Sendable {
        public let state: String
    }

    public struct CommitPayload: Encodable, Sendable {
        public let message: String
        public let shortSha: String
    }

    /// Maps the per-repo inputs into the `project-git-status` widget envelope (NIC-130). A read
    /// failure (the projects root is unavailable) is an honest `unavailable`; a readable-but-empty
    /// root is `empty`; otherwise `ready` with one report per repo. The local branch/sync always
    /// render — the GitHub half degrades independently per repo via ``gitHubReportPayload``.
    public static func projectGitStatusWidget(
        from result: Swift.Result<[ProjectGitStatusInput], Error>, now: Date
    ) -> ProjectGitStatusWidget {
        switch result {
        case .failure:
            return ProjectGitStatusWidget(
                widgetId: "project-git-status", state: "unavailable", headline: nil,
                emptyMessage: "Your projects folder isn't available.", freshness: nil, data: nil
            )
        case let .success(inputs) where inputs.isEmpty:
            return ProjectGitStatusWidget(
                widgetId: "project-git-status", state: "empty", headline: nil,
                emptyMessage: "No repositories in your projects folder yet.", freshness: nil, data: nil
            )
        case let .success(inputs):
            let repositories = inputs.map { input in
                ProjectGitStatusItemPayload(
                    id: input.id,
                    name: input.name,
                    branch: input.branch,
                    sync: input.sync?.rawValue,
                    remote: input.remote.map { GitHubRemotePayload(owner: $0.owner, repo: $0.repo) },
                    github: gitHubReportPayload(remote: input.remote, result: input.github)
                )
            }
            return ProjectGitStatusWidget(
                widgetId: "project-git-status", state: "ready",
                headline: inputs.count == 1 ? "1 repository" : "\(inputs.count) repositories",
                emptyMessage: nil,
                freshness: WidgetFreshnessPayload(observedAt: now, label: "just now"),
                data: ProjectGitStatusWidgetData(repositories: repositories)
            )
        }
    }

    /// Maps one repo's GitHub result into the payload's `github` field (NIC-130). No remote → nil
    /// (the web shows "Not a GitHub repository"). A ready report carries PRs, CI state, and commits;
    /// a missing credential guides the user to add their token; a rate limit is surfaced distinctly;
    /// any other failure is a generic unavailable — the raw diagnostic is never leaked.
    private static func gitHubReportPayload(
        remote: GitRemote?, result: Swift.Result<GitHubRepoReport, Error>?
    ) -> ProjectGitHubReportPayload? {
        guard remote != nil else { return nil }
        switch result {
        case let .success(report):
            return ProjectGitHubReportPayload(
                state: "ready",
                openPullRequests: OpenPullRequestsPayload(
                    count: report.openPullRequests.count, titles: report.openPullRequests.titles
                ),
                checks: ChecksPayload(state: report.checks.rawValue),
                recentCommits: report.recentCommits.map {
                    CommitPayload(message: $0.message, shortSha: $0.shortSha)
                },
                message: nil
            )
        case let .failure(error):
            return failureReportPayload(error)
        case .none:
            // A remote exists but no fetch was performed — an honest generic unavailable.
            return ProjectGitHubReportPayload(
                state: "unavailable", openPullRequests: nil, checks: nil, recentCommits: nil,
                message: "GitHub is unavailable right now."
            )
        }
    }

    private static func failureReportPayload(_ error: Error) -> ProjectGitHubReportPayload {
        if let status = error as? GitHubStatusError {
            switch status {
            case .credentialsMissing:
                return ProjectGitHubReportPayload(
                    state: "unavailable", openPullRequests: nil, checks: nil, recentCommits: nil,
                    message: "Add your GitHub token in Settings → Setup to see repo status."
                )
            case .rateLimited:
                return ProjectGitHubReportPayload(
                    state: "rate-limited", openPullRequests: nil, checks: nil, recentCommits: nil,
                    message: "GitHub is rate-limited. Try again shortly."
                )
            case .providerFailed:
                break // fall through to the generic message; the raw diagnostic is never surfaced
            }
        }
        return ProjectGitHubReportPayload(
            state: "unavailable", openPullRequests: nil, checks: nil, recentCommits: nil,
            message: "GitHub is unavailable right now."
        )
    }

    /// A `settings.changed` event (live cross-webview sync): the durable settings were
    /// updated through `updateSettings`, so every surface — the dashboard and the
    /// separate native settings window — reflects the new assistant name, mode colors,
    /// and motion preference immediately, not just on next launch. Carries the full
    /// resolved snapshot (the same shape as `getSettings`).
    public static func settingsChangedEvent(
        snapshot: CerebralHelmSettingsSnapshot, id: String, timestamp: Date
    ) -> CerebralHelmBridgeEvent {
        struct Wrapper: Encodable { let settings: CerebralHelmSettingsSnapshot }
        return CerebralHelmBridgeEvent(
            eventID: id,
            payload: encodedPayload(Wrapper(settings: snapshot)),
            schemaVersion: "1.0.0",
            timestamp: timestamp,
            type: .settingsChanged
        )
    }

    /// A `layout.session.changed` event (NIC-142): the active layout session was
    /// started, changed, or ended. Carries the session snapshot, or `null` when no
    /// layout is active (closed or ended by a mode switch). The bottom-bar layout
    /// section renders from this — it is the only source of the active-layout state.
    static func layoutSessionChangedEvent(
        session: LayoutSessionSnapshot?, id: String, timestamp: Date
    ) -> CerebralHelmBridgeEvent {
        struct Wrapper: Encodable {
            let session: LayoutSessionSnapshot?
            enum CodingKeys: String, CodingKey { case session }
            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                // Encode an explicit null when ended, so the dashboard distinguishes
                // "no active layout" from a payload that merely omitted the key.
                try container.encode(session, forKey: .session)
            }
        }
        return CerebralHelmBridgeEvent(
            eventID: id,
            payload: encodedPayload(Wrapper(session: session)),
            schemaVersion: "1.0.0",
            timestamp: timestamp,
            type: .layoutSessionChanged
        )
    }

    /// One channel of the `system.status.changed` metrics payload (NIC-81b).
    /// `sampledAt` timestamps the sample that produced the value, so stale data
    /// stays timestamped downstream (MAC-ADAPTER-3 AC).
    public struct SystemMetricsChannel: Encodable, Sendable {
        public let availability: String
        public let value: Double?
        public let unit: String?
        public let sampledAt: Date?

        public init(availability: String, value: Double?, unit: String?, sampledAt: Date?) {
            self.availability = availability
            self.value = value
            self.unit = unit
            self.sampledAt = sampledAt
        }
    }

    /// Battery keeps its charging flag for the dashboard's bolt indicator.
    public struct SystemMetricsBatteryChannel: Encodable, Sendable {
        public let availability: String
        public let value: Double?
        public let charging: Bool?
        public let pluggedIn: Bool?
        public let unit: String?
        public let sampledAt: Date?

        public init(availability: String, value: Double?, charging: Bool?, pluggedIn: Bool?, unit: String?, sampledAt: Date?) {
            self.availability = availability
            self.value = value
            self.charging = charging
            self.pluggedIn = pluggedIn
            self.unit = unit
            self.sampledAt = sampledAt
        }
    }

    /// Network carries the Wi-Fi link (transmit) rate — the connection's speed,
    /// not measured throughput (NIC-135).
    public struct SystemMetricsNetworkChannel: Encodable, Sendable {
        public let availability: String
        public let linkMbps: Double?
        public let unit: String?
        public let sampledAt: Date?

        public init(availability: String, linkMbps: Double?, unit: String?, sampledAt: Date?) {
            self.availability = availability
            self.linkMbps = linkMbps
            self.unit = unit
            self.sampledAt = sampledAt
        }
    }

    /// The `system.status.changed` metrics payload. The event *type* is shared
    /// with the bridge-failure/recovery posture events (NIC-64), so the payload
    /// carries `category: "system_metrics"` as the discriminator the dashboard
    /// reducer branches on.
    public struct SystemMetricsPayload: Encodable, Sendable {
        public let category = "system_metrics"
        public let cpu: SystemMetricsChannel
        public let memory: SystemMetricsChannel
        public let network: SystemMetricsNetworkChannel
        public let battery: SystemMetricsBatteryChannel
        public let display: SystemMetricsChannel

        public init(
            cpu: SystemMetricsChannel,
            memory: SystemMetricsChannel,
            network: SystemMetricsNetworkChannel,
            battery: SystemMetricsBatteryChannel,
            display: SystemMetricsChannel
        ) {
            self.cpu = cpu
            self.memory = memory
            self.network = network
            self.battery = battery
            self.display = display
        }
    }

    /// A `bridge.capability.changed` event (FR-SHL-06, NIC-83): one capability's
    /// availability transitioned at runtime — e.g. the user granted or revoked a
    /// platform permission in System Settings. The payload matches the dashboard
    /// reducer's shape: `{ capability: { id, available, degradedReason } }`.
    public static func capabilityChangedEvent(
        _ capability: CerebralContracts.Capability, id: String, timestamp: Date
    ) -> CerebralHelmBridgeEvent {
        struct Wrapper: Encodable {
            let capability: CerebralContracts.Capability
        }
        return CerebralHelmBridgeEvent(
            eventID: id,
            payload: encodedPayload(Wrapper(capability: capability)),
            schemaVersion: "1.0.0",
            timestamp: timestamp,
            type: .bridgeCapabilityChanged
        )
    }

    /// A `system.status.changed` event carrying one live metrics snapshot
    /// (NIC-81b). Emitted by the status publisher on its sampling cadence.
    public static func systemStatusEvent(
        _ metrics: SystemMetricsPayload, id: String, timestamp: Date
    ) -> CerebralHelmBridgeEvent {
        CerebralHelmBridgeEvent(
            eventID: id,
            payload: encodedPayload(metrics),
            schemaVersion: "1.0.0",
            timestamp: timestamp,
            type: .systemStatusChanged
        )
    }

    /// One connected display in the shell's topology (FR-SHL-06, NIC-87).
    /// `id` is the CoreGraphics display UUID when the platform can provide one;
    /// otherwise a session-scoped fallback with `stableIdentity: false`, so
    /// consumers never persist an identity the platform did not guarantee.
    public struct DisplayDescriptor: Encodable, Equatable, Sendable {
        public let id: String
        public let name: String
        public let frame: WindowRect
        public let primary: Bool
        public let stableIdentity: Bool

        public init(id: String, name: String, frame: WindowRect, primary: Bool, stableIdentity: Bool) {
            self.id = id
            self.name = name
            self.frame = frame
            self.primary = primary
            self.stableIdentity = stableIdentity
        }
    }

    /// The full display topology snapshot carried by `display.topology.changed`.
    /// Snapshots are compared whole (Equatable) — the observer only emits on a
    /// real transition, never on a redundant screen-parameter notification.
    public struct DisplayTopologyPayload: Encodable, Equatable, Sendable {
        public let displays: [DisplayDescriptor]
        public let primaryDisplayId: String?

        public init(displays: [DisplayDescriptor]) {
            self.displays = displays
            self.primaryDisplayId = displays.first(where: \.primary)?.id
        }
    }

    /// A `display.topology.changed` event (FR-SHL-06, NIC-87): a display was
    /// connected, disconnected, or rearranged — or the initial snapshot at
    /// observation start, so the dashboard always holds the current topology.
    public static func displayTopologyChangedEvent(
        _ topology: DisplayTopologyPayload, id: String, timestamp: Date
    ) -> CerebralHelmBridgeEvent {
        CerebralHelmBridgeEvent(
            eventID: id,
            payload: encodedPayload(topology),
            schemaVersion: "1.0.0",
            timestamp: timestamp,
            type: .displayTopologyChanged
        )
    }

    /// A `workflow.action.progress` event (FR-CMD-05): one step of an executing
    /// workflow / quick action started or reached its terminal status. The
    /// dashboard renders per-action progress from these without parsing logs.
    public static func workflowActionProgressEvent(
        _ progress: WorkflowActionProgress, id: String, timestamp: Date
    ) -> CerebralHelmBridgeEvent {
        struct Payload: Encodable {
            let commandId: String
            let workflowId: String
            let actionId: String
            let kind: String
            let status: String
            let index: Int
            let total: Int
            let message: String?
        }
        return CerebralHelmBridgeEvent(
            eventID: id,
            payload: encodedPayload(Payload(
                commandId: progress.commandID,
                workflowId: progress.workflowID,
                actionId: progress.actionID,
                kind: progress.kind,
                status: progress.status.rawValue,
                index: progress.index,
                total: progress.total,
                message: progress.message
            )),
            schemaVersion: "1.0.0",
            timestamp: timestamp,
            type: .workflowActionProgress
        )
    }

    /// Generates a schema-valid event id (`^brevt_[A-Za-z0-9_-]{8,64}$`).
    public static func newEventID() -> String {
        "brevt_" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
    }

    private static func encodedPayload<Payload: Encodable>(_ payload: Payload) -> [String: JSONAny] {
        guard
            let data = try? BridgeMessageCoding.encoder().encode(payload),
            let decoded = try? JSONDecoder().decode([String: JSONAny].self, from: data)
        else { return [:] }
        return decoded
    }

    /// `{ snapshot: <bootstrap minus modes/agents> }` — the mode-switch payload the
    /// dashboard reducer folds in.
    private static func snapshotPayload(_ snapshot: CerebralHelmBridgeBootstrapState) -> [String: JSONAny] {
        guard
            let data = try? BridgeMessageCoding.encoder().encode(snapshot),
            var dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        dict.removeValue(forKey: "modes")
        dict.removeValue(forKey: "agents")
        guard
            let wrapped = try? JSONSerialization.data(withJSONObject: ["snapshot": dict]),
            let payload = try? JSONDecoder().decode([String: JSONAny].self, from: wrapped)
        else { return [:] }
        return payload
    }

    private static func confirmationPayload(
        _ disclosure: CerebralHelmConfirmationDisclosure?
    ) -> [String: JSONAny] {
        struct Wrapper: Encodable { let confirmation: CerebralHelmConfirmationDisclosure? }
        guard
            let data = try? BridgeMessageCoding.encoder().encode(Wrapper(confirmation: disclosure)),
            let payload = try? JSONDecoder().decode([String: JSONAny].self, from: data)
        else { return [:] }
        return payload
    }

    private static func payload(_ event: CommandLifecycleEvent) -> [String: JSONAny] {
        guard
            let data = try? BridgeMessageCoding.encoder().encode(event),
            let payload = try? JSONDecoder().decode([String: JSONAny].self, from: data)
        else { return [:] }
        return payload
    }
}
