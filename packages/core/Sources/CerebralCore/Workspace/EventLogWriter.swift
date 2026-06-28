import Foundation

/// **Legacy / test-and-recovery only.** Appends command lifecycle events to a
/// development event log as newline-delimited JSON.
///
/// This NDJSON sink is **not** part of the production write path. Per
/// [ADR-006](../../../../docs/adr/ADR-006-sqlite-single-source-of-truth.md),
/// SQLite (via `CerebralStorage`) is the single source of truth for operational
/// history; this writer and its companion `EventLogReader` / `CommandStatusReader`
/// are demoted to test/fixture and recovery bindings behind the Core ports
/// (deterministic unit tests, fallback) rather than the runtime store.
///
/// As a bus subscriber it gives those test/recovery paths cross-invocation
/// visibility: once a command runs, its events are on disk for `events tail` and
/// `command status` to read. Writes are serialized so concurrent subscriber
/// callbacks cannot interleave a line.
public final class EventLogWriter: @unchecked Sendable {
    private let lock = NSLock()
    public let eventLogPath: URL

    public init(eventLogPath: URL) {
        self.eventLogPath = eventLogPath
    }

    public func append(_ event: CommandLifecycleEvent) throws {
        let data = try CommandCoding.makeEncoder().encode(event)
        var line = String(decoding: data, as: UTF8.self)
        line.append("\n")

        lock.lock()
        defer { lock.unlock() }

        try FileManager.default.createDirectory(
            at: eventLogPath.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if !FileManager.default.fileExists(atPath: eventLogPath.path) {
            try Data().write(to: eventLogPath)
        }
        let handle = try FileHandle(forWritingTo: eventLogPath)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(line.utf8))
    }
}
