import Foundation
import Testing

import CerebralStorage

/// NIC-95: bounded retention for the timestamped snapshots under `<stateRoot>/backups`.
///
/// These cover a destructive operation, so the emphasis is on what pruning must
/// *refuse* to delete rather than on the happy path alone.

private func temporaryRoot() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("cerebral-retention-\(UUID().uuidString)", isDirectory: true)
}

/// Creates a snapshot directory that looks real — i.e. carries a `manifest.json`.
private func makeSnapshot(_ backups: URL, named name: String) throws {
    let directory = backups.appendingPathComponent(name, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Data("{}".utf8).write(to: directory.appendingPathComponent("manifest.json"))
}

private func names(in directory: URL) throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
}

@Test("pruning keeps the newest N snapshots and removes the rest")
func prunesToTheKeepCount() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let backups = root.appendingPathComponent("backups", isDirectory: true)

    // Deliberately created out of order: ordering must come from the name, not
    // from filesystem creation time.
    for name in ["2026-06-03T000000Z", "2026-06-01T000000Z", "2026-06-05T000000Z",
                 "2026-06-02T000000Z", "2026-06-04T000000Z"] {
        try makeSnapshot(backups, named: name)
    }

    let removed = try BackupRetention.prune(backups, keeping: 2)

    #expect(removed == 3)
    #expect(try names(in: backups) == ["2026-06-04T000000Z", "2026-06-05T000000Z"])
}

@Test("a directory without a manifest is never a deletion candidate")
func leavesNonSnapshotsAlone() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let backups = root.appendingPathComponent("backups", isDirectory: true)

    try makeSnapshot(backups, named: "2026-06-01T000000Z")
    try makeSnapshot(backups, named: "2026-06-02T000000Z")
    // A partial snapshot from an interrupted run, and a folder the user parked here.
    let partial = backups.appendingPathComponent("2026-06-03T000000Z", isDirectory: true)
    try FileManager.default.createDirectory(at: partial, withIntermediateDirectories: true)
    let userFolder = backups.appendingPathComponent("my-notes", isDirectory: true)
    try FileManager.default.createDirectory(at: userFolder, withIntermediateDirectories: true)

    _ = try BackupRetention.prune(backups, keeping: 1)

    // Only the older *real* snapshot goes; neither unmanaged directory is touched.
    #expect(try names(in: backups) == ["2026-06-02T000000Z", "2026-06-03T000000Z", "my-notes"])
}

@Test("keeping is clamped to at least one, so a prune can never empty the directory")
func neverEmptiesTheDirectory() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let backups = root.appendingPathComponent("backups", isDirectory: true)

    try makeSnapshot(backups, named: "2026-06-01T000000Z")
    try makeSnapshot(backups, named: "2026-06-02T000000Z")

    _ = try BackupRetention.prune(backups, keeping: 0)

    #expect(try names(in: backups) == ["2026-06-02T000000Z"])
}

@Test("a single snapshot survives any prune")
func keepsTheOnlySnapshot() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let backups = root.appendingPathComponent("backups", isDirectory: true)
    try makeSnapshot(backups, named: "2026-06-01T000000Z")

    #expect(try BackupRetention.prune(backups, keeping: 0) == 0)
    #expect(try names(in: backups) == ["2026-06-01T000000Z"])
}

@Test("fewer snapshots than the keep count is a no-op")
func noOpBelowTheKeepCount() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let backups = root.appendingPathComponent("backups", isDirectory: true)
    try makeSnapshot(backups, named: "2026-06-01T000000Z")
    try makeSnapshot(backups, named: "2026-06-02T000000Z")

    #expect(try BackupRetention.prune(backups, keeping: 5) == 0)
    #expect(try names(in: backups).count == 2)
}

@Test("a missing backups directory is not an error")
func toleratesMissingDirectory() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    #expect(try BackupRetention.prune(root.appendingPathComponent("backups")) == 0)
}

@Test("snapshot tokens are filesystem-safe and sort in chronological order")
func tokensSortChronologically() {
    let earlier = BackupRetention.token(Date(timeIntervalSince1970: 1_700_000_000))
    let later = BackupRetention.token(Date(timeIntervalSince1970: 1_700_086_400))

    #expect(!earlier.contains(":"))
    #expect(!earlier.contains("/"))
    // Lexical order is what prune() relies on to identify the newest snapshots.
    #expect(earlier < later)
}
