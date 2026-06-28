import Foundation
import Testing
import CerebralShared
@testable import CerebralCore

// NIC-39 (PRE-MODE-4): active mode/context state and the mode session log —
// domain behavior with in-memory stores. FR-MOD-05 safe fallback, FR-MOD-06
// session fields + derived end times.

private struct FixedClock: TimeSource {
    let instant: Date
    func now() -> Date { instant }
}

private final class InMemoryStateStore: ModeStateStore, @unchecked Sendable {
    var modeID: String?
    var context: ProjectContext?
    func loadActiveModeID() throws -> String? { modeID }
    func saveActiveModeID(_ modeID: String?) throws { self.modeID = modeID }
    func loadActiveContext() throws -> ProjectContext? { context }
    func saveActiveContext(_ context: ProjectContext?) throws { self.context = context }
}

private final class InMemorySessionLog: ModeSessionLog, @unchecked Sendable {
    var sessions: [ModeSession] = []
    func append(_ session: ModeSession) throws { sessions.append(session) }
    func read() throws -> [ModeSession] { sessions }
}

// MARK: - FR-MOD-05 fallback

@Test("a persisted mode that still exists is restored")
func persistedModeRestored() {
    let resolved = ModeStateResolver.resolveActiveModeID(
        persisted: "developer", availableModeIDs: ["executive", "developer"], defaultModeID: "executive"
    )
    #expect(resolved == "developer")
}

@Test("a persisted mode that no longer exists falls back to the default")
func missingModeFallsBack() {
    let resolved = ModeStateResolver.resolveActiveModeID(
        persisted: "ghost", availableModeIDs: ["executive", "developer"], defaultModeID: "executive"
    )
    #expect(resolved == "executive")
}

@Test("no persisted mode falls back to the default")
func nilModeFallsBack() {
    let resolved = ModeStateResolver.resolveActiveModeID(
        persisted: nil, availableModeIDs: ["executive"], defaultModeID: "executive"
    )
    #expect(resolved == "executive")
}

// MARK: - FR-MOD-06 derived end times

@Test("session end times are derived as the next activation's start; the latest stays open")
func endTimesDerived() {
    let base = Date(timeIntervalSince1970: 1_000)
    let sessions = [
        ModeSession(id: "sess_1", modeID: "executive", context: nil, source: "cli", startedAt: base, result: .success, configVersion: "1.0.0"),
        ModeSession(id: "sess_2", modeID: "developer", context: nil, source: "cli", startedAt: base.addingTimeInterval(60), result: .partialSuccess, configVersion: "1.0.0"),
    ]

    let derived = ModeSessionHistory.withDerivedEnds(sessions)
    #expect(derived[0].endedAt == base.addingTimeInterval(60))
    #expect(derived[1].endedAt == nil)
}

// MARK: - Coordinator (FR-MOD-06 fields, FR-MOD-05 active mode)

@Test("recording an application appends a session with source, config version, and result")
func recordApplicationCapturesFields() throws {
    let store = InMemoryStateStore()
    let log = InMemorySessionLog()
    let coordinator = ModeSessionCoordinator(
        stateStore: store,
        sessionLog: log,
        identifiers: SequentialIdentifierGenerator(),
        clock: FixedClock(instant: Date(timeIntervalSince1970: 42))
    )

    let session = try coordinator.recordApplication(
        modeID: "developer",
        context: ProjectContext(id: "cerebral-helm", label: "CerebralHelm"),
        source: "cli",
        result: .partialSuccess,
        configVersion: "1.0.0"
    )

    #expect(session.id == "sess_00000001")
    #expect(session.source == "cli")
    #expect(session.configVersion == "1.0.0")
    #expect(session.result == .partialSuccess)
    #expect(session.startedAt == Date(timeIntervalSince1970: 42))
    #expect(log.sessions.count == 1)
    // The application becomes the active mode.
    #expect(store.modeID == "developer")
}

@Test("recording does not clear a context the user set separately")
func recordingLeavesContextStoreUntouched() throws {
    let store = InMemoryStateStore()
    try store.saveActiveContext(ProjectContext(id: "thesis"))
    let coordinator = ModeSessionCoordinator(
        stateStore: store, sessionLog: InMemorySessionLog(),
        identifiers: SequentialIdentifierGenerator(), clock: FixedClock(instant: Date())
    )

    _ = try coordinator.recordApplication(modeID: "school", context: nil, source: "cli", result: .success, configVersion: "1.0.0")

    // Mode/context persist separately: applying a mode does not wipe the context.
    #expect(store.context == ProjectContext(id: "thesis"))
}
