import Foundation
import Testing

import CerebralContracts
import CerebralCore
import CerebralShared

/// NIC-27: lifecycle, parser, concurrency, and cancellation regression tests.
///
/// These exercise the spine under concurrency with deterministic clocks and
/// identifiers (AC-27.1), assert that no command ever emits more than one
/// terminal event (AC-27.2), and repeat each race a fixed number of times so a
/// regression surfaces reliably in CI (AC-27.3).

// MARK: - Test doubles

private struct ScriptedExecutor: CommandExecutor {
    enum Mode: Sendable {
        case succeed
        case unavailable
        case confirmThenSucceed
        case confirmThenTimeout
    }

    let mode: Mode

    func requiresConfirmation(_ envelope: CommandEnvelope) -> Bool {
        mode == .confirmThenSucceed || mode == .confirmThenTimeout
    }

    func execute(_ envelope: CommandEnvelope) -> CommandOutcome {
        switch mode {
        case .succeed, .confirmThenSucceed:
            return .succeeded(summary: "ok")
        case .unavailable:
            return .unavailable(summary: "no adapter")
        case .confirmThenTimeout:
            return .failed(code: "timeout", message: "timed out", category: .timeout)
        }
    }
}

private final class EventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [CommandLifecycleEvent] = []

    func record(_ event: CommandLifecycleEvent) {
        lock.lock()
        storage.append(event)
        lock.unlock()
    }

    var events: [CommandLifecycleEvent] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

private struct SubscriberFailure: Error {}

private func deterministicFactory() -> CommandFactory {
    CommandFactory(
        clock: FixedClock(Date(timeIntervalSinceReferenceDate: 0), step: 1),
        identifiers: SequentialIdentifierGenerator()
    )
}

private func envelope(_ id: String, source: CommandSource = .cli) -> CommandEnvelope {
    CommandEnvelope(
        correlationID: nil,
        id: id,
        payload: [:],
        privacy: CommandPrivacy(cloudPolicy: .deny, sensitivity: .sensitivityPrivate),
        rawInput: "mode developer",
        schemaVersion: CommandContract.schemaVersion,
        source: source,
        timestamp: Date(timeIntervalSinceReferenceDate: 0),
        type: .commandSubmit
    )
}

private func terminalEvents(_ events: [CommandLifecycleEvent], commandId: String) -> [CommandLifecycleEvent] {
    events.filter { $0.commandID == commandId && CommandLifecycle.isTerminal($0.currentStatus) }
}

// MARK: - AC-27.2 parallel commands, ordering, single terminal

@Test("parallel submissions each reach exactly one ordered terminal event")
func parallelSubmissions() async throws {
    for _ in 0..<5 {
        let bus = CommandBus(factory: deterministicFactory(), executor: ScriptedExecutor(mode: .unavailable))
        let recorder = EventRecorder()
        bus.subscribe { recorder.record($0) }

        let count = 40
        await withTaskGroup(of: Void.self) { group in
            for index in 0..<count {
                group.addTask { _ = try? bus.submit(envelope("cmd_parallel\(index)")) }
            }
        }

        let events = recorder.events
        #expect(events.count == count * 4)

        let grouped = Dictionary(grouping: events, by: \.commandID)
        #expect(grouped.count == count)
        for (_, commandEvents) in grouped {
            // Per-command lifecycle order is preserved even though commands interleave.
            #expect(commandEvents.map(\.currentStatus) == [.received, .planned, .running, .failed])
            #expect(commandEvents.filter { CommandLifecycle.isTerminal($0.currentStatus) }.count == 1)
        }
    }
}

// MARK: - AC-27.2/AC-25.3 cancellation races

@Test("concurrent cancels of a pending command emit exactly one terminal event")
func concurrentCancelsAreIdempotent() async throws {
    for _ in 0..<10 {
        let bus = CommandBus(factory: deterministicFactory(), executor: ScriptedExecutor(mode: .confirmThenSucceed))
        let recorder = EventRecorder()
        bus.subscribe { recorder.record($0) }

        let id = "cmd_cancelrace01"
        _ = try bus.submit(envelope(id))

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<8 {
                group.addTask { _ = bus.cancel(commandId: id) }
            }
        }

        let terminals = terminalEvents(recorder.events, commandId: id)
        #expect(terminals.count == 1)
        #expect(terminals.first?.currentStatus == .cancelled)
        #expect(bus.status(of: id) == .cancelled)
    }
}

@Test("cancel racing approval still yields a single terminal event")
func cancelRacesApproval() async throws {
    for _ in 0..<10 {
        let bus = CommandBus(factory: deterministicFactory(), executor: ScriptedExecutor(mode: .confirmThenTimeout))
        let recorder = EventRecorder()
        bus.subscribe { recorder.record($0) }

        let id = "cmd_approvecancel1"
        _ = try bus.submit(envelope(id))

        await withTaskGroup(of: Void.self) { group in
            group.addTask { _ = bus.cancel(commandId: id) }
            group.addTask { _ = bus.decideConfirmation(commandId: id, approved: true) }
        }

        // Exactly one terminal event regardless of who won the race.
        #expect(terminalEvents(recorder.events, commandId: id).count == 1)
        let status = bus.status(of: id)
        #expect(status == .cancelled || status == .failed)
    }
}

// MARK: - Subscriber failure isolation under load

@Test("a throwing subscriber stays isolated under concurrent load")
func subscriberFailureIsolatedUnderLoad() async throws {
    let bus = CommandBus(factory: deterministicFactory(), executor: ScriptedExecutor(mode: .unavailable))
    let healthy = EventRecorder()
    bus.subscribe { _ in throw SubscriberFailure() }
    bus.subscribe { healthy.record($0) }

    let count = 30
    await withTaskGroup(of: Void.self) { group in
        for index in 0..<count {
            group.addTask { _ = try? bus.submit(envelope("cmd_load\(index)")) }
        }
    }

    #expect(healthy.events.count == count * 4)
    let grouped = Dictionary(grouping: healthy.events, by: \.commandID)
    #expect(grouped.count == count)
    for (_, commandEvents) in grouped {
        #expect(commandEvents.filter { CommandLifecycle.isTerminal($0.currentStatus) }.count == 1)
    }
}

// MARK: - Double completion

@Test("a terminal machine rejects every further transition")
func terminalMachineRejectsFurtherTransitions() throws {
    var machine = CommandLifecycleMachine(commandId: "cmd_terminalcheck1", factory: deterministicFactory())
    try machine.markReceived()
    try machine.markPlanned()
    try machine.markRunning()
    try machine.markSucceeded()

    for next in CommandLifecycle.allStatuses {
        #expect(throws: (any Error).self) {
            var copy = machine
            try copy.transition(to: next)
        }
    }
    #expect(machine.events.count == 4)
    #expect(machine.events.filter { CommandLifecycle.isTerminal($0.currentStatus) }.count == 1)
}

// MARK: - Parser regression

@Test("invalid grammar never resolves to an executable intent")
func invalidGrammarNeverExecutes() {
    let references = CommandReferences(
        apps: [ReferenceEntry(id: "vscode", label: "VS Code", target: "x")],
        urls: [ReferenceEntry(id: "github", label: "GitHub", target: "https://github.com")],
        hooks: [ReferenceEntry(id: "ondraft-dev", label: "Hook", target: "x")],
        modeIds: ["developer"]
    )
    let parser = DirectCommandParser(references: references)

    let invalidInputs = [
        "", "   ", "teleport home", "mode", "mode banana",
        "open", "open nope", "hook", "hook nope", "note", "search",
    ]
    for input in invalidInputs {
        if case .parsed = parser.parse(input) {
            Issue.record("input \"\(input)\" must not resolve to an executable intent")
        }
    }
}

// MARK: - AC-27.1 determinism

@Test("deterministic clock and ids produce identical event streams across runs")
func deterministicReplayIsStable() throws {
    func runOnce() throws -> [String] {
        let bus = CommandBus(factory: deterministicFactory(), executor: ScriptedExecutor(mode: .succeed))
        let recorder = EventRecorder()
        bus.subscribe { recorder.record($0) }
        for index in 1...3 {
            _ = try bus.submit(envelope("cmd_replay000\(index)"))
        }
        return recorder.events.map {
            "\($0.id)|\($0.commandID)|\($0.currentStatus.rawValue)|\($0.timestamp.timeIntervalSinceReferenceDate)"
        }
    }

    let first = try runOnce()
    let second = try runOnce()
    #expect(!first.isEmpty)
    #expect(first == second)
}
