import Foundation

/// The kind of identifier to mint. The prefix matches the contract id patterns
/// (`cmd_…`, `evt_…`, `corr_…`) used across the command and event schemas.
public enum IdentifierKind: Sendable {
    case command
    case event
    case correlation
    case confirmation

    /// Identifier prefix without the trailing underscore.
    public var prefix: String {
        switch self {
        case .command: return "cmd"
        case .event: return "evt"
        case .correlation: return "corr"
        case .confirmation: return "conf"
        }
    }
}

/// Injectable identifier generator for commands and lifecycle events.
///
/// Every produced identifier must satisfy the contract pattern
/// `^<prefix>_[A-Za-z0-9_-]{8,64}$`.
public protocol IdentifierGenerator: Sendable {
    func nextIdentifier(for kind: IdentifierKind) -> String
}

/// Production generator backed by a random UUID.
///
/// The 32-character lowercase hex suffix is within the contract's 8–64 length
/// bound and uses only the allowed character set.
public struct UUIDIdentifierGenerator: IdentifierGenerator {
    public init() {}

    public func nextIdentifier(for kind: IdentifierKind) -> String {
        let suffix = UUID().uuidString
            .replacingOccurrences(of: "-", with: "")
            .lowercased()
        return "\(kind.prefix)_\(suffix)"
    }
}

/// Deterministic generator backed by a monotonic counter.
///
/// Used by tests, fixtures, and simulations so identifiers are reproducible
/// (PRD NFR-04). The counter is shared across kinds, so a command followed by
/// its first event yields `cmd_00000001` then `evt_00000002`.
public final class SequentialIdentifierGenerator: IdentifierGenerator, @unchecked Sendable {
    private let lock = NSLock()
    private var counter: UInt64

    public init(start: UInt64 = 1) {
        self.counter = start
    }

    public func nextIdentifier(for kind: IdentifierKind) -> String {
        lock.lock()
        let value = counter
        counter += 1
        lock.unlock()

        var digits = String(value)
        if digits.count < 8 {
            digits = String(repeating: "0", count: 8 - digits.count) + digits
        }
        return "\(kind.prefix)_\(digits)"
    }
}
