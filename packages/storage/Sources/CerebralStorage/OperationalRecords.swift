import Foundation

/// Storage-layer record types for the operational command history.
///
/// These are deliberately plain (strings, dates, optionals) and decoupled from the
/// generated contract DTOs, so `CerebralStorage` stays self-contained and testable.
/// The app layer maps `CommandEnvelope` / `CommandLifecycleEvent` / the redacted
/// `CerebralHelmToolResult` onto these when it wires the repositories live (NIC-47
/// 4b). All free text reaching these rows is already redacted by the runtime
/// (NIC-34), so the records carry the `redacted*` naming as a reminder.

/// A row in `commands`.
public struct CommandRecord: Equatable, Sendable {
    public let id: String
    public let source: String
    public let redactedInput: String?
    public let sensitivity: String?
    public let cloudPolicy: String?
    public let status: String
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: String, source: String, redactedInput: String?, sensitivity: String?,
        cloudPolicy: String?, status: String, createdAt: Date, updatedAt: Date
    ) {
        self.id = id
        self.source = source
        self.redactedInput = redactedInput
        self.sensitivity = sensitivity
        self.cloudPolicy = cloudPolicy
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// A row in `command_events`.
public struct CommandEventRecord: Equatable, Sendable {
    public let id: String
    public let commandID: String
    public let status: String
    public let previousStatus: String?
    public let occurredAt: Date
    public let payload: String?

    public init(
        id: String, commandID: String, status: String, previousStatus: String?,
        occurredAt: Date, payload: String?
    ) {
        self.id = id
        self.commandID = commandID
        self.status = status
        self.previousStatus = previousStatus
        self.occurredAt = occurredAt
        self.payload = payload
    }
}

/// A row in `tool_calls` (the redacted record of one tool execution).
public struct ToolCallRecord: Equatable, Sendable {
    public let commandID: String
    public let toolID: String
    public let toolVersion: String
    public let adapterID: String
    public let status: String
    public let durationMs: Int?
    public let startedAt: Date
    public let completedAt: Date
    public let redactedInput: String?
    public let redactedOutput: String?
    public let errorCategory: String?
    public let errorCode: String?
    public let errorMessage: String?

    public init(
        commandID: String, toolID: String, toolVersion: String, adapterID: String,
        status: String, durationMs: Int?, startedAt: Date, completedAt: Date,
        redactedInput: String?, redactedOutput: String?,
        errorCategory: String?, errorCode: String?, errorMessage: String?
    ) {
        self.commandID = commandID
        self.toolID = toolID
        self.toolVersion = toolVersion
        self.adapterID = adapterID
        self.status = status
        self.durationMs = durationMs
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.redactedInput = redactedInput
        self.redactedOutput = redactedOutput
        self.errorCategory = errorCategory
        self.errorCode = errorCode
        self.errorMessage = errorMessage
    }
}

extension SQLiteValue {
    /// `.text` for a value, `.null` for `nil`.
    static func textOrNull(_ value: String?) -> SQLiteValue { value.map(SQLiteValue.text) ?? .null }
    /// `.integer` for a value, `.null` for `nil`.
    static func intOrNull(_ value: Int?) -> SQLiteValue { value.map { .integer(Int64($0)) } ?? .null }
    /// An ISO-8601 `.text` timestamp.
    static func timestamp(_ date: Date) -> SQLiteValue { .text(StorageTimestamp.iso8601(from: date)) }
}
