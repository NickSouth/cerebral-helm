import Foundation
import Testing

import CerebralStorage

/// NIC-47 (4a): operational command/event/tool-call repositories with transaction
/// boundaries (AC-47.1) and structured errors (AC-47.3).

private let c0 = Date(timeIntervalSince1970: 1_700_000_000)
private func at(_ offset: TimeInterval) -> Date { c0.addingTimeInterval(offset) }

private func migratedDatabase() throws -> SQLiteDatabase {
    let database = try SQLiteDatabase(location: .memory)
    _ = try SchemaMigrator().migrate(database)
    return database
}

private func command(_ id: String, status: String, created: Date, updated: Date) -> CommandRecord {
    CommandRecord(
        id: id, source: "cli", redactedInput: nil, sensitivity: "private",
        cloudPolicy: "deny", status: status, createdAt: created, updatedAt: updated
    )
}

private func event(_ id: String, _ commandID: String, _ status: String, previous: String?, at occurredAt: Date) -> CommandEventRecord {
    CommandEventRecord(id: id, commandID: commandID, status: status, previousStatus: previous, occurredAt: occurredAt, payload: "{\"type\":\"\(status)\"}")
}

@Test("a command and its lifecycle events round-trip in order")
func commandLifecycleRoundTrips() throws {
    let repo = CommandRepository(database: try migratedDatabase())

    try repo.upsert(command("cmd_00000001", status: "received", created: c0, updated: c0))
    try repo.append(event("evt_00000001", "cmd_00000001", "received", previous: nil, at: c0))
    try repo.record(
        command("cmd_00000001", status: "running", created: c0, updated: at(1)),
        event: event("evt_00000002", "cmd_00000001", "running", previous: "planned", at: at(1))
    )
    try repo.record(
        command("cmd_00000001", status: "succeeded", created: c0, updated: at(2)),
        event: event("evt_00000003", "cmd_00000001", "succeeded", previous: "running", at: at(2))
    )

    let stored = try repo.command(id: "cmd_00000001")
    #expect(stored?.status == "succeeded")
    #expect(stored?.updatedAt == at(2))
    #expect(stored?.createdAt == c0) // preserved across upserts

    #expect(try repo.events(commandID: "cmd_00000001").map(\.id) == ["evt_00000001", "evt_00000002", "evt_00000003"])
}

@Test("a failed event rolls back the command status update (AC-47.1)")
func terminalStatusAndEventAreAtomic() throws {
    let repo = CommandRepository(database: try migratedDatabase())
    try repo.upsert(command("cmd_00000001", status: "running", created: c0, updated: c0))
    try repo.append(event("evt_dup00001", "cmd_00000001", "running", previous: "planned", at: c0))

    // The terminal event reuses an existing event id, so its insert fails. Because
    // the status update and the event insert share one transaction, the command
    // must remain at its prior status rather than recording succeeded with no event.
    #expect(throws: StorageError.self) {
        try repo.record(
            command("cmd_00000001", status: "succeeded", created: c0, updated: at(2)),
            event: event("evt_dup00001", "cmd_00000001", "succeeded", previous: "running", at: at(2))
        )
    }

    #expect(try repo.command(id: "cmd_00000001")?.status == "running")
}

@Test("an event for an unknown command is a structured foreign-key error (AC-47.3)")
func eventForUnknownCommandFails() throws {
    let repo = CommandRepository(database: try migratedDatabase())
    do {
        try repo.append(event("evt_00000001", "cmd_missing01", "received", previous: nil, at: c0))
        Issue.record("expected a foreign-key constraint violation")
    } catch let error as StorageError {
        guard case .constraintViolation = error else {
            Issue.record("expected constraintViolation, got \(error)")
            return
        }
    }
}

@Test("upsert advances status while preserving the original row (idempotent)")
func upsertPreservesCreatedAt() throws {
    let repo = CommandRepository(database: try migratedDatabase())
    try repo.upsert(command("cmd_00000001", status: "received", created: c0, updated: c0))
    try repo.upsert(command("cmd_00000001", status: "succeeded", created: at(5), updated: at(3)))

    let stored = try repo.command(id: "cmd_00000001")
    #expect(stored?.status == "succeeded")
    #expect(stored?.createdAt == c0) // first insert wins; not overwritten on update
    #expect(try repo.recentCommands(limit: 10).count == 1)
}

@Test("recent commands are returned newest first within the limit")
func recentCommandsAreOrdered() throws {
    let repo = CommandRepository(database: try migratedDatabase())
    try repo.upsert(command("cmd_00000001", status: "succeeded", created: at(0), updated: at(0)))
    try repo.upsert(command("cmd_00000002", status: "succeeded", created: at(10), updated: at(10)))
    try repo.upsert(command("cmd_00000003", status: "succeeded", created: at(20), updated: at(20)))

    #expect(try repo.recentCommands(limit: 2).map(\.id) == ["cmd_00000003", "cmd_00000002"])
}

@Test("tool calls round-trip with nullable error and duration fields")
func toolCallsRoundTrip() throws {
    let database = try migratedDatabase()
    let commands = CommandRepository(database: database)
    let calls = ToolCallRepository(database: database)
    try commands.upsert(command("cmd_00000001", status: "succeeded", created: c0, updated: at(2)))

    try calls.record(ToolCallRecord(
        commandID: "cmd_00000001", toolID: "note.search", toolVersion: "1.0.0", adapterID: "mock_native",
        status: "success", durationMs: nil, startedAt: at(1), completedAt: at(2),
        redactedInput: "{\"query\":\"[REDACTED]\"}", redactedOutput: "{\"results\":[]}",
        errorCategory: nil, errorCode: nil, errorMessage: nil
    ))
    try calls.record(ToolCallRecord(
        commandID: "cmd_00000001", toolID: "hook.run", toolVersion: "1.0.0", adapterID: "mock_native",
        status: "failure", durationMs: 1200, startedAt: at(1), completedAt: at(2),
        redactedInput: "{}", redactedOutput: "{}",
        errorCategory: "internal_failure", errorCode: "tool.failed", errorMessage: "boom"
    ))

    let stored = try calls.calls(commandID: "cmd_00000001")
    #expect(stored.count == 2)
    #expect(stored[0].toolID == "note.search")
    #expect(stored[0].durationMs == nil)
    #expect(stored[1].durationMs == 1200)
    #expect(stored[1].errorCode == "tool.failed")
}

@Test("a tool call for an unknown command is a structured foreign-key error (AC-47.3)")
func toolCallForUnknownCommandFails() throws {
    let calls = ToolCallRepository(database: try migratedDatabase())
    #expect(throws: StorageError.self) {
        try calls.record(ToolCallRecord(
            commandID: "cmd_missing01", toolID: "note.search", toolVersion: "1.0.0", adapterID: "mock_native",
            status: "success", durationMs: nil, startedAt: c0, completedAt: at(1),
            redactedInput: nil, redactedOutput: nil, errorCategory: nil, errorCode: nil, errorMessage: nil
        ))
    }
}
