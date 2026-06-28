import Foundation

/// Persists the redacted record of each tool execution (FR-OBS-01, FR-OBS-03).
///
/// Each row references its command by foreign key, so the schema guarantees a
/// recorded tool call always belongs to a known command (FR-OBS-02). Input and
/// output are already redacted by the runtime before they reach here (NIC-34).
public struct ToolCallRepository: Sendable {
    private let database: SQLiteDatabase

    public init(database: SQLiteDatabase) {
        self.database = database
    }

    /// Appends a tool-call record, returning its assigned rowid.
    @discardableResult
    public func record(_ call: ToolCallRecord) throws -> Int64 {
        try database.run(
            """
            INSERT INTO tool_calls
                (command_id, tool_id, tool_version, adapter_id, status, duration_ms,
                 started_at, completed_at, redacted_input, redacted_output,
                 error_category, error_code, error_message)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """,
            [
                .text(call.commandID),
                .text(call.toolID),
                .text(call.toolVersion),
                .text(call.adapterID),
                .text(call.status),
                .intOrNull(call.durationMs),
                .timestamp(call.startedAt),
                .timestamp(call.completedAt),
                .textOrNull(call.redactedInput),
                .textOrNull(call.redactedOutput),
                .textOrNull(call.errorCategory),
                .textOrNull(call.errorCode),
                .textOrNull(call.errorMessage),
            ]
        )
        return database.lastInsertRowID
    }

    /// Tool calls for a command, in execution order.
    public func calls(commandID: String) throws -> [ToolCallRecord] {
        let rows = try database.query(
            """
            SELECT command_id, tool_id, tool_version, adapter_id, status, duration_ms,
                   started_at, completed_at, redacted_input, redacted_output,
                   error_category, error_code, error_message
            FROM tool_calls WHERE command_id = ? ORDER BY id;
            """,
            [.text(commandID)]
        )
        return rows.compactMap(Self.call(from:))
    }

    private static func call(from row: SQLiteRow) -> ToolCallRecord? {
        guard
            let commandID = row.text("command_id"),
            let toolID = row.text("tool_id"),
            let toolVersion = row.text("tool_version"),
            let adapterID = row.text("adapter_id"),
            let status = row.text("status"),
            let startedAt = row.text("started_at").flatMap(StorageTimestamp.date(from:)),
            let completedAt = row.text("completed_at").flatMap(StorageTimestamp.date(from:))
        else { return nil }
        return ToolCallRecord(
            commandID: commandID, toolID: toolID, toolVersion: toolVersion, adapterID: adapterID,
            status: status, durationMs: row.integer("duration_ms").map(Int.init),
            startedAt: startedAt, completedAt: completedAt,
            redactedInput: row.text("redacted_input"), redactedOutput: row.text("redacted_output"),
            errorCategory: row.text("error_category"), errorCode: row.text("error_code"),
            errorMessage: row.text("error_message")
        )
    }
}
