import Foundation
import CerebralCore

/// NDJSON-backed ``ModeSessionLog`` — a **demoted test/fixture binding**.
///
/// Per ADR-006, SQLite is the single source of truth for durable state: the
/// production ``ModeSessionLog`` is `CerebralStorage.SQLiteModeSessionLog`. This
/// NDJSON adapter is no longer the pre-Mac production path; it is retained as a
/// lightweight test/fixture binding behind the same port.
///
/// Each activation is one JSON line appended under the env-aware state root, so
/// history accrues without rewriting prior lines (end times are derived on read).
/// Writes are serialized so concurrent callers cannot interleave a line. Reads
/// skip blank lines and tolerate a trailing partial line from an interrupted
/// append, returning the well-formed sessions in order.
public final class NDJSONModeSessionLog: ModeSessionLog, @unchecked Sendable {
    private let lock = NSLock()
    private let path: URL

    public init(path: URL) {
        self.path = path
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    public func append(_ session: ModeSession) throws {
        var line = try Self.makeEncoder().encode(session)
        line.append(0x0A)

        lock.lock()
        defer { lock.unlock() }

        try FileManager.default.createDirectory(
            at: path.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        if !FileManager.default.fileExists(atPath: path.path) {
            try Data().write(to: path)
        }
        let handle = try FileHandle(forWritingTo: path)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
    }

    public func read() throws -> [ModeSession] {
        lock.lock()
        defer { lock.unlock() }

        guard let data = try? Data(contentsOf: path) else { return [] }
        let decoder = Self.makeDecoder()
        return String(decoding: data, as: UTF8.self)
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line in
                try? decoder.decode(ModeSession.self, from: Data(line.utf8))
            }
    }
}
