import Foundation
import CerebralCore

/// SQLite-backed ``ModeSessionLog`` (FR-MOD-06).
///
/// Each activation is one row in `mode_sessions`. Like the NDJSON adapter it
/// replaces, `endedAt` is stored as written (the coordinator appends it `nil`) and
/// end times are derived on read by the caller, so prior rows are never rewritten.
/// `read` returns sessions in activation order.
public struct SQLiteModeSessionLog: ModeSessionLog {
    private let database: SQLiteDatabase

    public init(database: SQLiteDatabase) {
        self.database = database
    }

    public func append(_ session: ModeSession) throws {
        try database.run(
            """
            INSERT INTO mode_sessions
                (id, mode_id, context_id, context_label, source, started_at, ended_at, result, config_version)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
            """,
            [
                .text(session.id),
                .text(session.modeID),
                .textOrNull(session.context?.id),
                .textOrNull(session.context?.label),
                .text(session.source),
                .timestamp(session.startedAt),
                session.endedAt.map(SQLiteValue.timestamp) ?? .null,
                .text(session.result.rawValue),
                .text(session.configVersion),
            ]
        )
    }

    public func read() throws -> [ModeSession] {
        let rows = try database.query(
            """
            SELECT id, mode_id, context_id, context_label, source, started_at, ended_at, result, config_version
            FROM mode_sessions ORDER BY started_at, id;
            """
        )
        return rows.compactMap(Self.session(from:))
    }

    private static func session(from row: SQLiteRow) -> ModeSession? {
        guard
            let id = row.text("id"),
            let modeID = row.text("mode_id"),
            let source = row.text("source"),
            let startedAt = row.text("started_at").flatMap(StorageTimestamp.date(from:)),
            let result = row.text("result").flatMap(ModeSessionResult.init(rawValue:)),
            let configVersion = row.text("config_version")
        else { return nil }
        let context = row.text("context_id").map { ProjectContext(id: $0, label: row.text("context_label")) }
        return ModeSession(
            id: id, modeID: modeID, context: context, source: source,
            startedAt: startedAt,
            endedAt: row.text("ended_at").flatMap(StorageTimestamp.date(from:)),
            result: result, configVersion: configVersion
        )
    }
}
