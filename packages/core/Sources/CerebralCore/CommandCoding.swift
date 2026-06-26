import Foundation

/// Canonical JSON coder for command-spine models.
///
/// The generated contract bindings encode dates with a plain `.iso8601`
/// strategy that cannot parse the fractional-second timestamps used by the
/// canonical fixtures (e.g. `2026-06-23T16:00:00.000Z`). This coder accepts
/// both fractional and non-fractional ISO-8601 on decode and always emits
/// fractional seconds on encode, so the spine round-trips against the
/// canonical schemas and fixtures.
public enum CommandCoding {
    /// A decoder that parses ISO-8601 timestamps with or without fractional
    /// seconds.
    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = ISO8601Timestamp.date(from: raw) {
                return date
            }
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Invalid ISO-8601 timestamp: \(raw)"
                )
            )
        }
        return decoder
    }

    /// An encoder that emits ISO-8601 timestamps with fractional seconds and
    /// sorted keys for deterministic output.
    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(ISO8601Timestamp.string(from: date))
        }
        return encoder
    }
}

/// Stateless ISO-8601 conversion helpers.
///
/// Formatters are created per call rather than cached so the coding closures
/// capture nothing — `ISO8601DateFormatter` is not `Sendable`, and the custom
/// coding strategy closures are `@Sendable` under strict concurrency.
private enum ISO8601Timestamp {
    static func date(from raw: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: raw) {
            return date
        }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: raw)
    }

    static func string(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
