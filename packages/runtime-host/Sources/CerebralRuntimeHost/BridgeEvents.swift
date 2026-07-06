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

    /// Network keeps its direction split for the dashboard's up/down display.
    public struct SystemMetricsNetworkChannel: Encodable, Sendable {
        public let availability: String
        public let uploadMbps: Double?
        public let downloadMbps: Double?
        public let unit: String?
        public let sampledAt: Date?

        public init(availability: String, uploadMbps: Double?, downloadMbps: Double?, unit: String?, sampledAt: Date?) {
            self.availability = availability
            self.uploadMbps = uploadMbps
            self.downloadMbps = downloadMbps
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
