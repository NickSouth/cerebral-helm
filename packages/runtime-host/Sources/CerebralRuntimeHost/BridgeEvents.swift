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
