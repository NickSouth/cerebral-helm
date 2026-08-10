import Foundation

/// Names and prunes the timestamped snapshot directories under
/// `<stateRoot>/backups` (FR-UPD-04).
///
/// Retention exists because backups are taken automatically before every schema
/// migration (see ``BackupGatedMigration``), so an unbounded directory would grow
/// by one full database copy per migration, forever.
public enum BackupRetention {
    /// How many snapshots survive a prune. Five keeps enough history to recover
    /// from a bad migration that was not noticed immediately, without letting the
    /// directory grow without bound.
    public static let defaultKeep = 5

    /// A filesystem-safe timestamp for a snapshot directory, e.g. `2026-06-28T170000Z`.
    ///
    /// The format is deliberately lexically sortable: ``prune(_:keeping:)`` orders
    /// snapshots by directory name rather than by filesystem timestamps, which are
    /// not preserved by copies, archives, or restores.
    public static func token(_ instant: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: instant).replacingOccurrences(of: ":", with: "")
    }

    /// Removes all but the newest `keeping` snapshots and returns how many were
    /// removed.
    ///
    /// This deletes user-recovery data, so it is deliberately conservative:
    ///
    /// - Only direct subdirectories that contain a readable `manifest.json` are
    ///   considered. Anything else under `backups/` — a partial snapshot from an
    ///   interrupted run, notes the user parked there, an unrelated folder — is
    ///   never a deletion candidate.
    /// - `keeping` is clamped to at least 1, so no call can empty the directory.
    /// - A snapshot that fails to delete is skipped rather than aborting the
    ///   sweep; pruning is housekeeping and must never block a migration.
    @discardableResult
    public static func prune(_ backupsDirectory: URL, keeping: Int = defaultKeep) throws -> Int {
        let keep = max(1, keeping)
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: backupsDirectory.path) else { return 0 }

        let entries = try fileManager.contentsOfDirectory(
            at: backupsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        let snapshots = entries
            .filter { url in
                let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
                guard isDirectory else { return false }
                return fileManager.fileExists(atPath: url.appendingPathComponent("manifest.json").path)
            }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }

        guard snapshots.count > keep else { return 0 }

        var removed = 0
        for snapshot in snapshots.dropFirst(keep) {
            do {
                try fileManager.removeItem(at: snapshot)
                removed += 1
            } catch {
                continue
            }
        }
        return removed
    }
}
