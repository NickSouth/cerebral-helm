import Foundation

/// Persists command and command-event history (FR-OBS-01, FR-OBS-02).
///
/// The headline guarantee is atomicity: ``record(_:event:)`` writes a command's
/// status and a lifecycle event in one transaction, so a succeeded command can
/// never be persisted without its terminal event, and a rolled-back event leaves
/// the command's prior status intact (AC-47.1). Foreign-key integrity is enforced
/// by the schema — an event for an unknown command fails as a structured
/// ``StorageError`` (AC-47.3).
public struct CommandRepository: Sendable {
    private let database: SQLiteDatabase

    public init(database: SQLiteDatabase) {
        self.database = database
    }

    /// Inserts a command or, if it already exists, advances its status and
    /// `updated_at`. The received-time fields and `created_at` are preserved.
    public func upsert(_ command: CommandRecord) throws {
        try insertCommand(command)
    }

    /// Atomically records a command's status and a lifecycle event (AC-47.1).
    public func record(_ command: CommandRecord, event: CommandEventRecord) throws {
        try database.transaction {
            try insertCommand(command)
            try insertEvent(event)
        }
    }

    /// Appends a lifecycle event for an existing command.
    public func append(_ event: CommandEventRecord) throws {
        try insertEvent(event)
    }

    public func command(id: String) throws -> CommandRecord? {
        let rows = try database.query(
            """
            SELECT id, source, redacted_input, sensitivity, cloud_policy, status, created_at, updated_at
            FROM commands WHERE id = ?;
            """,
            [.text(id)]
        )
        return rows.first.flatMap(Self.command(from:))
    }

    /// Events for a command, in occurrence order.
    public func events(commandID: String) throws -> [CommandEventRecord] {
        let rows = try database.query(
            """
            SELECT id, command_id, status, previous_status, occurred_at, payload
            FROM command_events WHERE command_id = ? ORDER BY occurred_at, id;
            """,
            [.text(commandID)]
        )
        return rows.compactMap(Self.event(from:))
    }

    /// The most recent commands, newest first.
    public func recentCommands(limit: Int) throws -> [CommandRecord] {
        let rows = try database.query(
            """
            SELECT id, source, redacted_input, sensitivity, cloud_policy, status, created_at, updated_at
            FROM commands ORDER BY created_at DESC, id DESC LIMIT ?;
            """,
            [.integer(Int64(limit))]
        )
        return rows.compactMap(Self.command(from:))
    }

    // MARK: - Statements

    private func insertCommand(_ command: CommandRecord) throws {
        try database.run(
            """
            INSERT INTO commands (id, source, redacted_input, sensitivity, cloud_policy, status, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET status = excluded.status, updated_at = excluded.updated_at;
            """,
            [
                .text(command.id),
                .text(command.source),
                .textOrNull(command.redactedInput),
                .textOrNull(command.sensitivity),
                .textOrNull(command.cloudPolicy),
                .text(command.status),
                .timestamp(command.createdAt),
                .timestamp(command.updatedAt),
            ]
        )
    }

    private func insertEvent(_ event: CommandEventRecord) throws {
        try database.run(
            """
            INSERT INTO command_events (id, command_id, status, previous_status, occurred_at, payload)
            VALUES (?, ?, ?, ?, ?, ?);
            """,
            [
                .text(event.id),
                .text(event.commandID),
                .text(event.status),
                .textOrNull(event.previousStatus),
                .timestamp(event.occurredAt),
                .textOrNull(event.payload),
            ]
        )
    }

    // MARK: - Row mapping

    private static func command(from row: SQLiteRow) -> CommandRecord? {
        guard
            let id = row.text("id"),
            let source = row.text("source"),
            let status = row.text("status"),
            let createdAt = row.text("created_at").flatMap(StorageTimestamp.date(from:)),
            let updatedAt = row.text("updated_at").flatMap(StorageTimestamp.date(from:))
        else { return nil }
        return CommandRecord(
            id: id, source: source, redactedInput: row.text("redacted_input"),
            sensitivity: row.text("sensitivity"), cloudPolicy: row.text("cloud_policy"),
            status: status, createdAt: createdAt, updatedAt: updatedAt
        )
    }

    private static func event(from row: SQLiteRow) -> CommandEventRecord? {
        guard
            let id = row.text("id"),
            let commandID = row.text("command_id"),
            let status = row.text("status"),
            let occurredAt = row.text("occurred_at").flatMap(StorageTimestamp.date(from:))
        else { return nil }
        return CommandEventRecord(
            id: id, commandID: commandID, status: status,
            previousStatus: row.text("previous_status"), occurredAt: occurredAt,
            payload: row.text("payload")
        )
    }
}
