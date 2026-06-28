import Foundation

/// Canonical ISO-8601 timestamp encode/decode for durable state.
///
/// Both storage rows (`schema_migrations.applied_at`, repository writes) and
/// Markdown note frontmatter (`created`/`updated`/`reviewAfter`) persist instants
/// as ISO-8601 strings, and they must round-trip identically across the whole
/// codebase. This is the single source of those format options
/// (`[.withInternetDateTime, .withFractionalSeconds]`); the storage and knowledge
/// helpers are thin wrappers over it so the on-disk format never diverges.
///
/// A fresh formatter is created per call to avoid shared mutable state;
/// timestamp encode/decode is infrequent relative to that cost.
public enum ISO8601Timestamp {
    /// The instant encoded as an ISO-8601 string with fractional seconds.
    public static func string(from date: Date) -> String {
        formatter().string(from: date)
    }

    /// The instant parsed from an ISO-8601 string, or `nil` if it does not match.
    public static func date(from string: String) -> Date? {
        formatter().date(from: string)
    }

    private static func formatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }
}
