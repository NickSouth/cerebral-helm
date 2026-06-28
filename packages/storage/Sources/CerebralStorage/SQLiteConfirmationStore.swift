import Foundation
import CerebralCore
import CerebralShared

/// SQLite-backed ``ConfirmationStore`` (FR-SAF-05, FR-OBS-01).
///
/// Persists one pending confirmation per command in the `confirmations` table, so
/// the single-use `used` flag and absolute `expires_at` survive a process restart
/// — a token requested in one `cerebral` invocation is decidable in the next
/// (NIC-112), instead of resolving to `unknownToken` against a fresh in-memory map.
/// `save` upserts on `command_id`, giving the supersede-on-replan behavior the
/// coordinator relies on.
public struct SQLiteConfirmationStore: ConfirmationStore {
    private let database: SQLiteDatabase
    private let clock: any TimeSource

    public init(database: SQLiteDatabase, clock: any TimeSource = SystemClock()) {
        self.database = database
        self.clock = clock
    }

    public func load(commandID: String) throws -> PendingConfirmation? {
        let rows = try database.query(
            """
            SELECT command_id, confirmation_id, token_value, plan_hash, expires_at, used
            FROM confirmations WHERE command_id = ?;
            """,
            [.text(commandID)]
        )
        guard
            let row = rows.first,
            let expiresAtString = row.text("expires_at"),
            let expiresAt = StorageTimestamp.date(from: expiresAtString)
        else { return nil }

        return PendingConfirmation(
            commandID: row.text("command_id") ?? commandID,
            confirmationID: row.text("confirmation_id") ?? "",
            tokenValue: row.text("token_value") ?? "",
            planHash: row.text("plan_hash") ?? "",
            expiresAt: expiresAt,
            used: (row.integer("used") ?? 0) == 1
        )
    }

    public func save(_ pending: PendingConfirmation) throws {
        // created_at is set on first insert and preserved on supersede/update.
        try database.run(
            """
            INSERT INTO confirmations
                (command_id, confirmation_id, token_value, plan_hash, expires_at, used, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(command_id) DO UPDATE SET
                confirmation_id = excluded.confirmation_id,
                token_value = excluded.token_value,
                plan_hash = excluded.plan_hash,
                expires_at = excluded.expires_at,
                used = excluded.used;
            """,
            [
                .text(pending.commandID),
                .text(pending.confirmationID),
                .text(pending.tokenValue),
                .text(pending.planHash),
                .text(StorageTimestamp.iso8601(from: pending.expiresAt)),
                .integer(pending.used ? 1 : 0),
                .text(StorageTimestamp.iso8601(from: clock.now())),
            ]
        )
    }

    public func delete(commandID: String) throws {
        try database.run("DELETE FROM confirmations WHERE command_id = ?;", [.text(commandID)])
    }
}
