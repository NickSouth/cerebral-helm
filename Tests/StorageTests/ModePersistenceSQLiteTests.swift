import Foundation
import Testing

import CerebralCore
import CerebralShared
import CerebralStorage

/// NIC-47 (4c): the SQLite mode-state and mode-session adapters that replace the
/// file/NDJSON adapters as the production stores (FR-MOD-05, FR-MOD-06, ADR-006).

private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

private func temporaryDatabaseURL() -> (directory: URL, url: URL) {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("cerebral-mode-\(UUID().uuidString)", isDirectory: true)
    return (directory, directory.appendingPathComponent("cerebral.sqlite"))
}

private func openMigrated(_ url: URL) throws -> SQLiteDatabase {
    let database = try SQLiteDatabase(location: .file(url))
    _ = try SchemaMigrator().migrate(database)
    return database
}

@Test("active mode and context round-trip across a fresh store (restart)")
func modeStateSurvivesRestart() throws {
    let (directory, url) = temporaryDatabaseURL()
    defer { try? FileManager.default.removeItem(at: directory) }

    do {
        let store = SQLiteModeStateStore(database: try openMigrated(url))
        try store.saveActiveModeID("developer")
        try store.saveActiveContext(ProjectContext(id: "proj-1", label: "Helm"))
    }

    let store = SQLiteModeStateStore(database: try openMigrated(url))
    #expect(try store.loadActiveModeID() == "developer")
    #expect(try store.loadActiveContext() == ProjectContext(id: "proj-1", label: "Helm"))
}

@Test("mode and context are persisted separately (FR-MOD-05)")
func modeAndContextAreSeparate() throws {
    let (directory, url) = temporaryDatabaseURL()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = SQLiteModeStateStore(database: try openMigrated(url))

    try store.saveActiveContext(ProjectContext(id: "proj-1"))
    try store.saveActiveModeID("school")
    // Saving the mode did not disturb the context.
    #expect(try store.loadActiveContext()?.id == "proj-1")
    #expect(try store.loadActiveModeID() == "school")

    try store.saveActiveModeID("developer")
    #expect(try store.loadActiveContext()?.id == "proj-1") // still present

    // Clearing the context leaves the mode intact.
    try store.saveActiveContext(nil)
    #expect(try store.loadActiveContext() == nil)
    #expect(try store.loadActiveModeID() == "developer")
}

@Test("mode sessions round-trip in order with derived end times (FR-MOD-06)")
func modeSessionsRoundTrip() throws {
    let (directory, url) = temporaryDatabaseURL()
    defer { try? FileManager.default.removeItem(at: directory) }
    let log = SQLiteModeSessionLog(database: try openMigrated(url))

    try log.append(ModeSession(
        id: "sess_000001", modeID: "developer", context: nil, source: "cli",
        startedAt: t0, endedAt: nil, result: .success, configVersion: "1.0.0"
    ))
    try log.append(ModeSession(
        id: "sess_000002", modeID: "school", context: ProjectContext(id: "c2", label: "L2"),
        source: "cli", startedAt: t0.addingTimeInterval(60), endedAt: nil,
        result: .partialSuccess, configVersion: "1.0.0"
    ))

    let sessions = ModeSessionHistory.withDerivedEnds(try log.read())
    #expect(sessions.map(\.id) == ["sess_000001", "sess_000002"])
    #expect(sessions[0].endedAt == t0.addingTimeInterval(60)) // derived as the next start
    #expect(sessions[1].endedAt == nil)                       // latest stays open
    #expect(sessions[1].context == ProjectContext(id: "c2", label: "L2"))
    #expect(sessions[1].result == .partialSuccess)
}

@Test("the coordinator records a session and sets the active mode in SQLite")
func coordinatorRecordsToSQLite() throws {
    let (directory, url) = temporaryDatabaseURL()
    defer { try? FileManager.default.removeItem(at: directory) }

    do {
        let database = try openMigrated(url)
        let coordinator = ModeSessionCoordinator(
            stateStore: SQLiteModeStateStore(database: database),
            sessionLog: SQLiteModeSessionLog(database: database),
            identifiers: SequentialIdentifierGenerator(),
            clock: FixedClock(t0)
        )
        try coordinator.recordApplication(
            modeID: "developer", context: nil, source: "cli", result: .success, configVersion: "1.0.0"
        )
    }

    // A fresh connection sees the active mode and the session (AC: restart restores state).
    let database = try openMigrated(url)
    #expect(try SQLiteModeStateStore(database: database).loadActiveModeID() == "developer")
    #expect(try SQLiteModeSessionLog(database: database).read().map(\.modeID) == ["developer"])
}
