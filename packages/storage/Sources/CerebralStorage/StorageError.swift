import Foundation

/// A structured failure from the operational SQLite store.
///
/// The cases mirror the storage failure states the canonical fixtures describe
/// (`fixtures/catalog/canonical-states.json`: `sqlite_locked`, and the read-only /
/// missing / corrupt classes exercised by PRE-DATA-7). Repository code maps SQLite
/// result codes to these cases so callers can react without importing the C API,
/// and so later increments can attach recovery guidance (FR-SHL-05) in one place.
public enum StorageError: Error, Equatable, Sendable, CustomStringConvertible {
    /// The database file does not exist (and creation was not requested) or could
    /// not be opened. Maps from `SQLITE_CANTOPEN`.
    case cannotOpen(String)
    /// The database is locked by another writer. Maps from `SQLITE_BUSY` / `SQLITE_LOCKED`.
    case locked(String)
    /// The database (or its directory) is read-only. Maps from `SQLITE_READONLY`.
    case readOnly(String)
    /// The database file is malformed or not a database. Maps from `SQLITE_CORRUPT` / `SQLITE_NOTADB`.
    case corrupt(String)
    /// A write violated a schema constraint. Maps from `SQLITE_CONSTRAINT`.
    case constraintViolation(String)
    /// Any other SQLite failure, carrying the engine's message.
    case message(String)

    /// The underlying SQLite message carried by the failure.
    public var detail: String {
        switch self {
        case let .cannotOpen(message),
             let .locked(message),
             let .readOnly(message),
             let .corrupt(message),
             let .constraintViolation(message),
             let .message(message):
            return message
        }
    }

    public var description: String {
        switch self {
        case let .cannotOpen(message): return "cannotOpen: \(message)"
        case let .locked(message): return "locked: \(message)"
        case let .readOnly(message): return "readOnly: \(message)"
        case let .corrupt(message): return "corrupt: \(message)"
        case let .constraintViolation(message): return "constraintViolation: \(message)"
        case let .message(message): return "message: \(message)"
        }
    }
}
