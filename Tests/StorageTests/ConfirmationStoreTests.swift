import Foundation
import Testing

import CerebralContracts
import CerebralCore
import CerebralShared
import CerebralStorage

/// NIC-112: cross-invocation confirmation persistence. A confirmation requested in
/// one process must be decidable in the next, with the single-use, expiry, and
/// plan-change guards (FR-SAF-05) surviving the restart — instead of resolving to
/// `unknownToken` against a fresh in-memory map.

private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

private func samplePlan(commandID: String, hookValue: String = "ondraft-dev") -> ConfirmationPlan {
    ConfirmationPlan(
        commandID: commandID,
        toolID: "hook.run",
        toolVersion: "1.0.0",
        toolPurpose: "Execute a configured allowlisted hook.",
        risk: .shell,
        destination: nil,
        accountOrService: nil,
        dataLeavingDevice: .none,
        reversibility: .unknown,
        arguments: [ConfirmationArgument(name: "hookId", value: hookValue, sensitive: false)],
        actionSummary: "Run hook \(hookValue)",
        policyReason: "Shell execution requires confirmation."
    )
}

/// Opens (creating if needed) and migrates the operational database at `url`.
/// Re-opening the same path models a process restart.
private func openMigrated(_ url: URL) throws -> SQLiteDatabase {
    let database = try SQLiteDatabase(location: .file(url))
    _ = try SchemaMigrator().migrate(database)
    return database
}

private func coordinator(_ database: SQLiteDatabase, clock: any TimeSource, ttl: TimeInterval = 120) -> ConfirmationCoordinator {
    ConfirmationCoordinator(
        clock: clock,
        identifiers: UUIDIdentifierGenerator(),
        ttlSeconds: ttl,
        store: SQLiteConfirmationStore(database: database)
    )
}

@Test("the SQLite store saves, loads, updates the used flag, supersedes, and deletes")
func storeRoundTrips() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("cerebral-conf-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = SQLiteConfirmationStore(database: try openMigrated(directory.appendingPathComponent("cerebral.sqlite")))

    let pending = PendingConfirmation(
        commandID: "cmd_abcdef01", confirmationID: "conf_abcdef01", tokenValue: "conf_token0001",
        planHash: "sha256:aa", expiresAt: t0.addingTimeInterval(120), used: false
    )
    try store.save(pending)
    #expect(try store.load(commandID: "cmd_abcdef01") == pending)
    #expect(try store.load(commandID: "cmd_missing01") == nil)

    var used = pending
    used.used = true
    try store.save(used)
    #expect(try store.load(commandID: "cmd_abcdef01")?.used == true)

    try store.delete(commandID: "cmd_abcdef01")
    #expect(try store.load(commandID: "cmd_abcdef01") == nil)
}

@Test("a confirmation requested in one process is approved in the next; replay still fails (AC-112.1)")
func confirmationSurvivesRestart() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("cerebral-conf-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("cerebral.sqlite")
    let clock = FixedClock(t0)

    // Invocation A: request a confirmation, then the process ends.
    let token: ConfirmationToken
    do {
        let coordinatorA = coordinator(try openMigrated(url), clock: clock)
        token = coordinatorA.requestConfirmation(plan: samplePlan(commandID: "cmd_restart0001")).token
    }

    // Invocation B: a brand-new coordinator and store over the same file decides it.
    let coordinatorB = coordinator(try openMigrated(url), clock: clock)
    #expect(coordinatorB.decide(token: token, decision: .approve)
        == .approved(confirmationID: token.confirmationID, commandID: token.commandID))

    // Invocation C: the single-use guard survived, so a replay is refused.
    let coordinatorC = coordinator(try openMigrated(url), clock: clock)
    #expect(coordinatorC.decide(token: token, decision: .approve) == .rejected(.alreadyUsed))
}

@Test("an expired token is refused after a restart (AC-112.1)")
func expirySurvivesRestart() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("cerebral-conf-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("cerebral.sqlite")

    let token: ConfirmationToken
    do {
        let coordinatorA = coordinator(try openMigrated(url), clock: FixedClock(t0), ttl: 60)
        token = coordinatorA.requestConfirmation(plan: samplePlan(commandID: "cmd_expiry0001")).token
    }

    // A later process, past the persisted expiry, refuses the token.
    let coordinatorB = coordinator(try openMigrated(url), clock: FixedClock(t0.addingTimeInterval(120)))
    #expect(coordinatorB.decide(token: token, decision: .approve) == .rejected(.expired))
}

@Test("a superseding request across a restart invalidates the old token (AC-112.1)")
func supersedeSurvivesRestart() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("cerebral-conf-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("cerebral.sqlite")
    let clock = FixedClock(t0)

    let firstToken: ConfirmationToken
    do {
        let coordinatorA = coordinator(try openMigrated(url), clock: clock)
        firstToken = coordinatorA.requestConfirmation(
            plan: samplePlan(commandID: "cmd_replan0001", hookValue: "ondraft-dev")
        ).token
    }

    // A new request for the same command, after restart, supersedes the stored row.
    let coordinatorB = coordinator(try openMigrated(url), clock: clock)
    let secondToken = coordinatorB.requestConfirmation(
        plan: samplePlan(commandID: "cmd_replan0001", hookValue: "ondraft-prod")
    ).token

    #expect(coordinatorB.decide(token: firstToken, decision: .approve) == .rejected(.planChanged))
    #expect(coordinatorB.decide(token: secondToken, decision: .approve)
        == .approved(confirmationID: secondToken.confirmationID, commandID: secondToken.commandID))
}
