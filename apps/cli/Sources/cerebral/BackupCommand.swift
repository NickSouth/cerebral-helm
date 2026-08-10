import Foundation
import ArgumentParser
import CerebralRuntimeHost
import CerebralStorage

/// `cerebral backup` — create and verify a timestamped snapshot of durable state
/// (operational database + user configuration + knowledge manifest). This is the
/// recovery-side counterpart to the updater's pre-migration backup (FR-UPD-04).
struct Backup: ParsableCommand {
    nonisolated(unsafe) static let configuration = CommandConfiguration(
        abstract: "Create and verify a backup of durable state."
    )

    @OptionGroup var options: GlobalOptions

    func run() throws {
        let paths = try workspacePaths(options)
        // Ensure the operational database exists and is current before snapshotting.
        _ = try operationalDatabase(paths)

        let now = Date()
        let destination = paths.backupsDirectory
            .appendingPathComponent(BackupRetention.token(now), isDirectory: true)
        let service = makeBackupService(paths)
        let manifest = try service.createBackup(into: destination, now: now)
        try service.verify(at: destination)
        // A manual backup prunes on the same policy as the automatic pre-migration
        // one, so `backups/` has a single bound however snapshots were created.
        try? BackupRetention.prune(paths.backupsDirectory)

        if options.json {
            print("{\"backedUp\":true,\"path\":\"\(destination.path)\",\"notes\":\(manifest.knowledge.count)}")
        } else {
            print("Backed up and verified \(manifest.knowledge.count) note(s) to \(destination.path).")
        }
    }
}
