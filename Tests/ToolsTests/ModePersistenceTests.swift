import Foundation
import Testing
import CerebralShared
import CerebralCore
import CerebralTools

// NIC-39 (PRE-MODE-4): the file/NDJSON state adapters, exercised against an
// isolated temporary state root. Proves the three acceptance criteria end to end
// on disk: restart restores valid state, missing/corrupt references fall back
// safely, and recorded sessions carry source, config version, and result.

private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private func tempPaths() throws -> WorkspacePaths {
    try WorkspacePaths.temporary(repositoryRoot: repositoryRoot())
}

private func makeStore(_ paths: WorkspacePaths) -> FileModeStateStore {
    FileModeStateStore(activeModePath: paths.activeModePath, activeContextPath: paths.activeContextPath)
}

// MARK: - AC: restart restores valid state

@Test("a saved active mode and context survive a fresh store instance (restart)")
func stateSurvivesRestart() throws {
    let paths = try tempPaths()
    let writer = makeStore(paths)
    try writer.saveActiveModeID("developer")
    try writer.saveActiveContext(ProjectContext(id: "cerebral-helm", label: "CerebralHelm"))

    // A new instance simulates a restarted process reading the same files.
    let reader = makeStore(paths)
    #expect(try reader.loadActiveModeID() == "developer")
    #expect(try reader.loadActiveContext() == ProjectContext(id: "cerebral-helm", label: "CerebralHelm"))
}

// MARK: - AC: missing references fall back safely

@Test("a fresh workspace loads nil state, and the resolver falls back to the default mode")
func missingStateFallsBack() throws {
    let store = makeStore(try tempPaths())
    #expect(try store.loadActiveModeID() == nil)
    #expect(try store.loadActiveContext() == nil)

    let resolved = ModeStateResolver.resolveActiveModeID(
        persisted: try store.loadActiveModeID(),
        availableModeIDs: ["executive", "developer"],
        defaultModeID: "executive"
    )
    #expect(resolved == "executive")
}

@Test("a corrupt state file loads as nil rather than throwing")
func corruptStateLoadsNil() throws {
    let paths = try tempPaths()
    try FileManager.default.createDirectory(at: paths.activeModePath.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("{ not json".utf8).write(to: paths.activeModePath)

    #expect(try makeStore(paths).loadActiveModeID() == nil)
}

@Test("clearing context removes the file so a stale value cannot reappear")
func clearingContextRemovesFile() throws {
    let store = makeStore(try tempPaths())
    try store.saveActiveContext(ProjectContext(id: "thesis"))
    try store.saveActiveContext(nil)
    #expect(try store.loadActiveContext() == nil)
}

// MARK: - AC: sessions include source, config version, result

@Test("appended sessions round-trip in order with derived end times")
func sessionLogRoundTrips() throws {
    let log = NDJSONModeSessionLog(path: try tempPaths().modeSessionLogPath)
    let base = Date(timeIntervalSince1970: 1_000)
    try log.append(ModeSession(id: "sess_1", modeID: "executive", context: nil, source: "cli", startedAt: base, result: .success, configVersion: "1.0.0"))
    try log.append(ModeSession(id: "sess_2", modeID: "developer", context: ProjectContext(id: "repo"), source: "cli", startedAt: base.addingTimeInterval(30), result: .partialSuccess, configVersion: "1.0.0"))

    let read = try log.read()
    #expect(read.map(\.id) == ["sess_1", "sess_2"])

    let derived = ModeSessionHistory.withDerivedEnds(read)
    #expect(derived[0].endedAt == base.addingTimeInterval(30))
    #expect(derived[1].endedAt == nil)
}

@Test("the coordinator records an application and makes it the active mode on disk")
func coordinatorRecordsToDisk() throws {
    let paths = try tempPaths()
    let store = makeStore(paths)
    let log = NDJSONModeSessionLog(path: paths.modeSessionLogPath)
    let coordinator = ModeSessionCoordinator(
        stateStore: store, sessionLog: log,
        identifiers: SequentialIdentifierGenerator(), clock: SystemClock()
    )

    try coordinator.recordApplication(
        modeID: "developer", context: ProjectContext(id: "cerebral-helm"),
        source: "cli", result: .partialSuccess, configVersion: "1.0.0"
    )

    let recorded = try log.read()
    #expect(recorded.count == 1)
    #expect(recorded[0].source == "cli")
    #expect(recorded[0].configVersion == "1.0.0")
    #expect(recorded[0].result == .partialSuccess)
    // Active mode persisted for the next process to restore.
    #expect(try makeStore(paths).loadActiveModeID() == "developer")
}
