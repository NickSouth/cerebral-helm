import Foundation

/// The durable state of one pending confirmation, keyed by command id.
///
/// This is the persistence shape behind ``ConfirmationCoordinator``: the token
/// value, the plan hash it is bound to, its absolute expiry, and the single-use
/// `used` flag. Persisting `expiresAt` and `used` is what lets the expiry and
/// replay guards (FR-SAF-05) survive a process restart (NIC-112).
public struct PendingConfirmation: Equatable, Sendable {
    public let commandID: String
    public let confirmationID: String
    public let tokenValue: String
    public let planHash: String
    public let expiresAt: Date
    public var used: Bool

    public init(
        commandID: String,
        confirmationID: String,
        tokenValue: String,
        planHash: String,
        expiresAt: Date,
        used: Bool
    ) {
        self.commandID = commandID
        self.confirmationID = confirmationID
        self.tokenValue = tokenValue
        self.planHash = planHash
        self.expiresAt = expiresAt
        self.used = used
    }
}

/// The seam behind which the confirmation coordinator stores pending tokens.
///
/// The pre-Mac foundation defaults to ``InMemoryConfirmationStore`` (per-process,
/// the historical behavior). PRE-DATA binds a SQLite-backed adapter
/// (`CerebralStorage.SQLiteConfirmationStore`) so a confirmation requested in one
/// `cerebral` invocation is decidable in the next, mirroring how
/// ``ModeStateStore`` / ``ModeSessionLog`` are file-backed today and SQLite-backed
/// under NIC-42. `save` overwrites any existing row for the same command id, which
/// is the supersede-on-replan behavior the coordinator relies on (AC-31.2).
public protocol ConfirmationStore: Sendable {
    /// The pending confirmation for `commandID`, or `nil` if none is stored.
    func load(commandID: String) throws -> PendingConfirmation?
    /// Stores `pending`, replacing any existing row for the same command id.
    func save(_ pending: PendingConfirmation) throws
    /// Removes the pending confirmation for `commandID` (idempotent).
    func delete(commandID: String) throws
}

/// In-memory confirmation store: the default, per-process backend.
///
/// Lock-serialized so concurrent decisions see a consistent map. State is lost
/// when the process exits — durable cross-invocation behavior comes from the
/// SQLite adapter.
public final class InMemoryConfirmationStore: ConfirmationStore, @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String: PendingConfirmation] = [:]

    public init() {}

    public func load(commandID: String) throws -> PendingConfirmation? {
        lock.lock(); defer { lock.unlock() }
        return entries[commandID]
    }

    public func save(_ pending: PendingConfirmation) throws {
        lock.lock(); defer { lock.unlock() }
        entries[pending.commandID] = pending
    }

    public func delete(commandID: String) throws {
        lock.lock(); defer { lock.unlock() }
        entries[commandID] = nil
    }
}
