import Foundation

/// Prunes old operational records with a safe default boundary (FR-OBS-05).
///
/// Pruning only ever touches *operational* rows — commands (cascading their events
/// and tool calls) and pending confirmations. It never deletes durable knowledge
/// (`note_metadata`, and the Markdown bodies it points at), the migration history,
/// the update history, settings metadata, or mode sessions (AC-47.2). ISO-8601
/// timestamps share one fixed format, so a lexicographic `<` is a chronological
/// comparison.
public struct OperationalRetention: Sendable {
    private let database: SQLiteDatabase

    public init(database: SQLiteDatabase) {
        self.database = database
    }

    /// Deletes commands and confirmations created strictly before `cutoff`,
    /// returning the number of command rows removed. Events and tool calls of a
    /// pruned command are removed by the schema's `ON DELETE CASCADE`.
    @discardableResult
    public func prune(olderThan cutoff: Date) throws -> Int {
        let boundary = StorageTimestamp.iso8601(from: cutoff)
        var removedCommands = 0
        try database.transaction {
            removedCommands = try database.run(
                "DELETE FROM commands WHERE created_at < ?;", [.text(boundary)]
            )
            try database.run(
                "DELETE FROM confirmations WHERE created_at < ?;", [.text(boundary)]
            )
        }
        return removedCommands
    }
}
