import Foundation
import Testing

import CerebralCore
import CerebralShared

/// NIC-26 (part 2): action surfaces wired through the real bus, event-log
/// persistence, status reconstruction, and simulation previews.

private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // CoreModelTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // repository root
}

/// Builds a session against the real config but an isolated, within-repo state
/// root so tests never touch the shared dev event log.
private func makeSession() throws -> (CerebralSession, WorkspacePaths, URL) {
    let root = repositoryRoot()
    let relative = ".local/session-test-\(UUID().uuidString)"
    let paths = try WorkspacePaths(repositoryRoot: root, environment: ["CEREBRAL_STATE_ROOT": relative])
    let session = try CerebralSession(
        paths: paths,
        clock: FixedClock(Date(timeIntervalSinceReferenceDate: 0), step: 1),
        identifiers: SequentialIdentifierGenerator()
    )
    return (session, paths, root.appendingPathComponent(relative))
}

// MARK: - Submission through the bus + persistence

@Test("a parsed command runs through the bus and persists its events")
func parsedCommandRunsAndPersists() throws {
    let (session, paths, cleanup) = try makeSession()
    defer { try? FileManager.default.removeItem(at: cleanup) }

    let outcome = try session.run("mode developer", source: .cli)

    // The stub pre-Mac executor has no adapter, so the command fails as
    // unavailable rather than reporting false success.
    guard case let .executed(commandId, status, _) = outcome else {
        Issue.record("expected executed, got \(outcome)")
        return
    }
    #expect(commandId == "cmd_00000001")
    #expect(status == .failed)

    // All four lifecycle events were persisted, in order.
    let tail = try EventLogReader.tail(paths.eventLogPath, lines: 10)
    #expect(tail.count == 4)

    // And status is reconstructable from the log across "invocations".
    let record = try session.status(of: commandId)
    #expect(record?.status == .failed)
}

@Test("unrecognized input is rejected and writes no events")
func unrecognizedInputIsRejected() throws {
    let (session, paths, cleanup) = try makeSession()
    defer { try? FileManager.default.removeItem(at: cleanup) }

    let outcome = try session.run("teleport home", source: .cli)

    guard case let .rejected(reason, _) = outcome else {
        Issue.record("expected rejected, got \(outcome)")
        return
    }
    #expect(reason.contains("Unknown command"))
    #expect(try EventLogReader.tail(paths.eventLogPath, lines: 10).isEmpty)
}

// MARK: - Simulation preview

@Test("a simulation fixture renders a deterministic preview without executing")
func simulationRendersPreview() throws {
    let root = repositoryRoot()
    let paths = try WorkspacePaths(repositoryRoot: root)
    let preview = try SimulationPreviewLoader.load(
        id: "successful-developer-mode",
        fixturesDirectory: paths.fixturesDirectory
    )

    #expect(preview.modeId == "developer")
    #expect(!preview.steps.isEmpty)

    let human = CliRenderer.human(preview)
    #expect(human.contains("Simulation: successful-developer-mode"))

    let json = try CliRenderer.json(preview)
    #expect(try JSONDecoder().decode(SimulationPreview.self, from: Data(json.utf8)) == preview)
}

// MARK: - Rendering

@Test("run outcomes render in human and JSON forms")
func runOutcomeRenders() throws {
    let executed = RunOutcome.executed(commandId: "cmd_00000001", status: .failed, summary: "No adapter.")
    #expect(CliRenderer.human(executed).contains("status:  failed"))
    #expect(try CliRenderer.json(executed).contains("\"executed\""))

    let rejected = RunOutcome.rejected(reason: "Unknown command 'x'.", suggestions: ["open <app|url>"])
    #expect(CliRenderer.human(rejected).contains("Suggestions:"))
    #expect(try CliRenderer.json(rejected).contains("\"rejected\""))
}

@Test("a missing command status renders a clear not-found result")
func statusNotFoundRenders() throws {
    let human = CliRenderer.human(nil, commandId: "cmd_does_not_exist")
    #expect(human.contains("No record found"))
    let json = try CliRenderer.json(nil, commandId: "cmd_does_not_exist")
    #expect(json.contains("\"found\" : false"))
}
