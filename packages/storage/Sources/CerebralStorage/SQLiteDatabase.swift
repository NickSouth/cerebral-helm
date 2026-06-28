import Foundation
import SwiftToolchainCSQLite

/// A column value crossing the Swift / SQLite boundary.
public enum SQLiteValue: Equatable, Sendable {
    case integer(Int64)
    case real(Double)
    case text(String)
    case blob([UInt8])
    case null
}

/// One result row: ordered column values plus name lookup.
public struct SQLiteRow: Equatable, Sendable {
    public let columns: [String]
    private let values: [SQLiteValue]
    private let indexByName: [String: Int]

    init(columns: [String], values: [SQLiteValue]) {
        self.columns = columns
        self.values = values
        var index: [String: Int] = [:]
        for (position, name) in columns.enumerated() { index[name] = position }
        self.indexByName = index
    }

    /// The value for `column`, or `nil` if the query selected no such column.
    public subscript(_ column: String) -> SQLiteValue? {
        guard let position = indexByName[column] else { return nil }
        return values[position]
    }

    public subscript(_ position: Int) -> SQLiteValue { values[position] }

    public func integer(_ column: String) -> Int64? {
        if case let .integer(value)? = self[column] { return value }
        return nil
    }

    public func text(_ column: String) -> String? {
        if case let .text(value)? = self[column] { return value }
        return nil
    }

    public func double(_ column: String) -> Double? {
        if case let .real(value)? = self[column] { return value }
        return nil
    }

    public func blob(_ column: String) -> [UInt8]? {
        if case let .blob(value)? = self[column] { return value }
        return nil
    }
}

/// `SQLITE_TRANSIENT` tells SQLite to copy a bound value during the bind call, so
/// a temporary Swift buffer can be passed safely.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// A thin, serialized wrapper over a single SQLite connection.
///
/// This is deliberately minimal: open/close, statement execution with typed
/// binds, row reads, and a transaction helper. It owns no schema — migrations
/// (PRE-DATA-4) and repositories (PRE-DATA-5) build on top of it. GRDB is the
/// post-Mac target (tracked as tech debt); pre-Mac this foundation uses the
/// vendored amalgamation `SwiftToolchainCSQLite` because it is the only SQLite
/// engine that builds on the Windows toolchain (see ADR-005).
///
/// All access is serialized by a recursive lock so a ``transaction(_:)`` body may
/// re-enter the public methods on the same thread while still excluding other
/// threads for the whole transaction.
public final class SQLiteDatabase: @unchecked Sendable {
    /// Where the database lives.
    public enum Location: Sendable {
        case memory
        case file(URL)
    }

    private var handle: OpaquePointer?
    private let lock = NSRecursiveLock()

    /// Opens a connection. File locations create their parent directory and the
    /// database file unless `create` is `false` (used to detect a missing file).
    /// Foreign-key enforcement is turned on for every connection, since the
    /// `PRAGMA` is per-connection and cannot live in a migration.
    public init(location: Location, create: Bool = true, busyTimeoutMs: Int32 = 5000) throws {
        let filename: String
        var flags: Int32 = SQLITE_OPEN_READWRITE
        switch location {
        case .memory:
            filename = ":memory:"
            flags |= SQLITE_OPEN_CREATE
        case let .file(url):
            filename = Self.sqlitePath(for: url)
            if create {
                flags |= SQLITE_OPEN_CREATE
                try? FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(), withIntermediateDirectories: true
                )
            }
        }

        var connection: OpaquePointer?
        let rc = sqlite3_open_v2(filename, &connection, flags, nil)
        guard rc == SQLITE_OK, let opened = connection else {
            let message = connection.map { String(cString: sqlite3_errmsg($0)) } ?? "Unable to open the database."
            sqlite3_close_v2(connection)
            throw Self.mapError(code: rc, message: message)
        }
        self.handle = opened
        sqlite3_busy_timeout(opened, busyTimeoutMs)
        try exec("PRAGMA foreign_keys = ON;")
    }

    deinit { sqlite3_close_v2(handle) }

    // MARK: - Public API

    /// Runs one or more statements with no parameters and no result rows (DDL).
    public func execute(_ sql: String) throws {
        lock.lock(); defer { lock.unlock() }
        try exec(sql)
    }

    /// Runs a single parameterized statement, returning the number of changed rows.
    @discardableResult
    public func run(_ sql: String, _ parameters: [SQLiteValue] = []) throws -> Int {
        lock.lock(); defer { lock.unlock() }
        return try runStatement(sql, parameters)
    }

    /// Runs a single parameterized query, returning every result row.
    public func query(_ sql: String, _ parameters: [SQLiteValue] = []) throws -> [SQLiteRow] {
        lock.lock(); defer { lock.unlock() }
        return try queryStatement(sql, parameters)
    }

    /// Executes `body` inside a transaction. Commits on return; rolls back and
    /// rethrows if `body` throws. The connection lock is held for the whole
    /// transaction, so its statements cannot interleave with another thread's.
    public func transaction<T>(_ body: () throws -> T) throws -> T {
        lock.lock(); defer { lock.unlock() }
        try exec("BEGIN;")
        do {
            let result = try body()
            try exec("COMMIT;")
            return result
        } catch {
            try? exec("ROLLBACK;")
            throw error
        }
    }

    /// The rowid of the most recent successful insert on this connection.
    public var lastInsertRowID: Int64 {
        lock.lock(); defer { lock.unlock() }
        return sqlite3_last_insert_rowid(handle)
    }

    // MARK: - Primitives (lock held by callers)

    private func exec(_ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(handle, sql, nil, nil, &errorMessage)
        defer { sqlite3_free(errorMessage) }
        guard rc == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? currentMessage()
            throw Self.mapError(code: rc, message: message)
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        let rc = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        guard rc == SQLITE_OK, let prepared = statement else {
            let message = currentMessage()
            sqlite3_finalize(statement)
            throw Self.mapError(code: rc, message: message)
        }
        return prepared
    }

    private func bind(_ statement: OpaquePointer, _ parameters: [SQLiteValue]) throws {
        for (offset, value) in parameters.enumerated() {
            let index = Int32(offset + 1)
            let rc: Int32
            switch value {
            case let .integer(number):
                rc = sqlite3_bind_int64(statement, index, number)
            case let .real(number):
                rc = sqlite3_bind_double(statement, index, number)
            case let .text(string):
                rc = sqlite3_bind_text(statement, index, string, -1, SQLITE_TRANSIENT)
            case let .blob(bytes):
                rc = bytes.withUnsafeBytes { buffer in
                    sqlite3_bind_blob(statement, index, buffer.baseAddress, Int32(buffer.count), SQLITE_TRANSIENT)
                }
            case .null:
                rc = sqlite3_bind_null(statement, index)
            }
            guard rc == SQLITE_OK else { throw Self.mapError(code: rc, message: currentMessage()) }
        }
    }

    private func runStatement(_ sql: String, _ parameters: [SQLiteValue]) throws -> Int {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        try bind(statement, parameters)
        let rc = sqlite3_step(statement)
        guard rc == SQLITE_DONE || rc == SQLITE_ROW else {
            throw Self.mapError(code: rc, message: currentMessage())
        }
        return Int(sqlite3_changes(handle))
    }

    private func queryStatement(_ sql: String, _ parameters: [SQLiteValue]) throws -> [SQLiteRow] {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        try bind(statement, parameters)

        let columnCount = Int(sqlite3_column_count(statement))
        var names: [String] = []
        names.reserveCapacity(columnCount)
        for column in 0..<columnCount {
            if let namePointer = sqlite3_column_name(statement, Int32(column)) {
                names.append(String(cString: namePointer))
            } else {
                names.append("column\(column)")
            }
        }

        var rows: [SQLiteRow] = []
        while true {
            let rc = sqlite3_step(statement)
            if rc == SQLITE_DONE { break }
            guard rc == SQLITE_ROW else { throw Self.mapError(code: rc, message: currentMessage()) }
            var values: [SQLiteValue] = []
            values.reserveCapacity(columnCount)
            for column in 0..<columnCount {
                values.append(readColumn(statement, Int32(column)))
            }
            rows.append(SQLiteRow(columns: names, values: values))
        }
        return rows
    }

    private func readColumn(_ statement: OpaquePointer, _ index: Int32) -> SQLiteValue {
        switch sqlite3_column_type(statement, index) {
        case SQLITE_INTEGER:
            return .integer(sqlite3_column_int64(statement, index))
        case SQLITE_FLOAT:
            return .real(sqlite3_column_double(statement, index))
        case SQLITE_TEXT:
            if let cString = sqlite3_column_text(statement, index) {
                return .text(String(cString: cString))
            }
            return .text("")
        case SQLITE_BLOB:
            let count = Int(sqlite3_column_bytes(statement, index))
            if count > 0, let pointer = sqlite3_column_blob(statement, index) {
                return .blob([UInt8](UnsafeRawBufferPointer(start: pointer, count: count)))
            }
            return .blob([])
        default:
            return .null
        }
    }

    private func currentMessage() -> String {
        guard let handle else { return "No open database connection." }
        return String(cString: sqlite3_errmsg(handle))
    }

    // MARK: - Helpers

    private static func mapError(code: Int32, message: String) -> StorageError {
        switch code & 0xFF {
        case SQLITE_CANTOPEN:
            return .cannotOpen(message)
        case SQLITE_BUSY, SQLITE_LOCKED:
            return .locked(message)
        case SQLITE_READONLY:
            return .readOnly(message)
        case SQLITE_CORRUPT, SQLITE_NOTADB:
            return .corrupt(message)
        case SQLITE_CONSTRAINT:
            return .constraintViolation(message)
        default:
            return .message("SQLite error \(code): \(message)")
        }
    }

    /// Normalizes a file URL into a path SQLite accepts. On Windows `URL.path`
    /// can yield a leading-slash drive path (`/C:/dir/db`); SQLite wants `C:/dir/db`.
    private static func sqlitePath(for url: URL) -> String {
        var path = url.standardizedFileURL.path
        let characters = Array(path)
        if characters.count >= 3, characters[0] == "/", characters[1].isLetter, characters[2] == ":" {
            path.removeFirst()
        }
        return path
    }
}
