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

    /// Generates a schema-valid event id (`^brevt_[A-Za-z0-9_-]{8,64}$`).
    public static func newEventID() -> String {
        "brevt_" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
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
