import Foundation

/// The outcome recorded for a mode session, mirroring `mode.apply`'s status.
public enum ModeSessionResult: String, Codable, Equatable, Sendable {
    case success
    case partialSuccess = "partial_success"
    case failed
}

/// One recorded mode activation (FR-MOD-06).
///
/// Field shape matches the future SQLite `mode_sessions` table (mode, context,
/// source, start/end, config version, result) so NIC-42 PRE-DATA back-fills it
/// without reshaping. Pre-SQLite the log is append-only: `endedAt` is left `nil`
/// at write time and derived on read as the next activation's start
/// (``ModeSessionHistory/withDerivedEnds(_:)``), keeping history queryable
/// without mutating prior lines.
public struct ModeSession: Codable, Equatable, Sendable {
    public let id: String
    public let modeID: String
    public let context: ProjectContext?
    public let source: String
    public let startedAt: Date
    public let endedAt: Date?
    public let result: ModeSessionResult
    public let configVersion: String

    public init(
        id: String,
        modeID: String,
        context: ProjectContext?,
        source: String,
        startedAt: Date,
        endedAt: Date? = nil,
        result: ModeSessionResult,
        configVersion: String
    ) {
        self.id = id
        self.modeID = modeID
        self.context = context
        self.source = source
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.result = result
        self.configVersion = configVersion
    }

    /// Returns a copy with a derived end time (the append-only log never rewrites
    /// a stored line; ends are computed on read).
    public func endingAt(_ endedAt: Date?) -> ModeSession {
        ModeSession(
            id: id, modeID: modeID, context: context, source: source,
            startedAt: startedAt, endedAt: endedAt, result: result, configVersion: configVersion
        )
    }
}

/// Append-only history of mode activations (FR-MOD-06).
///
/// The pre-Mac foundation binds an NDJSON adapter
/// (`CerebralTools.NDJSONModeSessionLog`); NIC-42 PRE-DATA swaps a SQLite-backed
/// adapter behind the same port. `read` returns sessions in activation order;
/// rich querying is deferred to NIC-42.
public protocol ModeSessionLog: Sendable {
    func append(_ session: ModeSession) throws
    func read() throws -> [ModeSession]
}

public enum ModeSessionHistory {
    /// Derives each session's end time as the next activation's start, leaving the
    /// most recent session open. Input is assumed to be in activation order.
    public static func withDerivedEnds(_ sessions: [ModeSession]) -> [ModeSession] {
        sessions.enumerated().map { index, session in
            let nextStart = index + 1 < sessions.count ? sessions[index + 1].startedAt : nil
            return session.endingAt(nextStart)
        }
    }
}
