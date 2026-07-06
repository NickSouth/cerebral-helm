import Foundation
import CerebralCore

/// In-memory ``ModeStateStore``: the default test/dev binding when no durable
/// store is composed. Thread-safe; state lives only for the process.
public final class InMemoryModeStateStore: ModeStateStore, @unchecked Sendable {
    private let lock = NSLock()
    private var modeID: String?
    private var context: ProjectContext?

    public init() {}

    public func loadActiveModeID() throws -> String? {
        lock.lock(); defer { lock.unlock() }
        return modeID
    }

    public func saveActiveModeID(_ modeID: String?) throws {
        lock.lock(); defer { lock.unlock() }
        self.modeID = modeID
    }

    public func loadActiveContext() throws -> ProjectContext? {
        lock.lock(); defer { lock.unlock() }
        return context
    }

    public func saveActiveContext(_ context: ProjectContext?) throws {
        lock.lock(); defer { lock.unlock() }
        self.context = context
    }
}

/// In-memory append-only ``ModeSessionLog``: the default test/dev binding when
/// no durable log is composed.
public final class InMemoryModeSessionLog: ModeSessionLog, @unchecked Sendable {
    private let lock = NSLock()
    private var sessions: [ModeSession] = []

    public init() {}

    public func append(_ session: ModeSession) throws {
        lock.lock(); defer { lock.unlock() }
        sessions.append(session)
    }

    public func read() throws -> [ModeSession] {
        lock.lock(); defer { lock.unlock() }
        return sessions
    }
}
