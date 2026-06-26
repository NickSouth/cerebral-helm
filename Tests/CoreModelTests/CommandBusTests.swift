import Foundation
import Testing

import CerebralContracts
import CerebralCore
import CerebralShared

/// NIC-25: in-process command bus and subscriptions.

private struct ScriptedExecutor: CommandExecutor {
    enum Mode: Sendable {
        case succeed
        case unavailable
        case confirmThenSucceed
    }

    let mode: Mode

    func requiresConfirmation(_ envelope: CommandEnvelope) -> Bool {
        mode == .confirmThenSucceed
    }

    func execute(_ envelope: CommandEnvelope) -> CommandOutcome {
        switch mode {
        case .succeed, .confirmThenSucceed:
            return .succeeded(summary: "Completed.")
        case .unavailable:
            return .unavailable(summary: "No adapter.")
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

    var statuses: [CommandStatus] {
        lock.lock()
        defer { lock.unlock() }
        return storage.map(\.currentStatus)
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return storage.count
    }
}

private struct ListenerFailure: Error {}

private func makeBus(_ mode: ScriptedExecutor.Mode = .succeed) -> CommandBus {
    let factory = CommandFactory(
        clock: FixedClock(Date(timeIntervalSinceReferenceDate: 0), step: 1),
        identifiers: SequentialIdentifierGenerator()
    )
    return CommandBus(factory: factory, executor: ScriptedExecutor(mode: mode))
}

private func makeEnvelope(source: CommandSource = .cli, id: String) -> CommandEnvelope {
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

// MARK: - AC-25.1 subscribers receive ordered events

@Test("multiple subscribers receive the same ordered event stream")
func subscribersReceiveOrderedEvents() throws {
    let bus = makeBus(.succeed)
    let first = EventRecorder()
    let second = EventRecorder()
    bus.subscribe { first.record($0) }
    bus.subscribe { second.record($0) }

    let receipt = try bus.submit(makeEnvelope(id: "cmd_00000000000000000000aaaa"))

    #expect(receipt.status == .succeeded)
    let expected: [CommandStatus] = [.received, .planned, .running, .succeeded]
    #expect(first.statuses == expected)
    #expect(second.statuses == expected)
}

// MARK: - AC-25.2 one subscriber failure does not corrupt command state

@Test("a throwing subscriber does not affect other subscribers or command state")
func subscriberFailureIsIsolated() throws {
    let bus = makeBus(.succeed)
    let healthy = EventRecorder()
    bus.subscribe { _ in throw ListenerFailure() }
    bus.subscribe { healthy.record($0) }

    let receipt = try bus.submit(makeEnvelope(id: "cmd_00000000000000000000bbbb"))

    #expect(receipt.status == .succeeded)
    #expect(healthy.statuses == [.received, .planned, .running, .succeeded])
    #expect(bus.status(of: "cmd_00000000000000000000bbbb") == .succeeded)
}

// MARK: - AC-25.3 cancellation is idempotent

@Test("cancelling a pending command is idempotent and emits one terminal event")
func cancellationIsIdempotent() throws {
    let bus = makeBus(.confirmThenSucceed)
    let recorder = EventRecorder()
    bus.subscribe { recorder.record($0) }

    let id = "cmd_00000000000000000000cccc"
    let submitReceipt = try bus.submit(makeEnvelope(id: id))
    #expect(submitReceipt.status == .requiresConfirmation)

    let firstCancel = bus.cancel(commandId: id)
    #expect(firstCancel?.status == .cancelled)
    let countAfterFirst = recorder.count

    let secondCancel = bus.cancel(commandId: id)
    #expect(secondCancel?.status == .cancelled)

    // No new event on the second cancel, and exactly one cancelled event.
    #expect(recorder.count == countAfterFirst)
    #expect(recorder.statuses.filter { $0 == .cancelled }.count == 1)
    #expect(bus.status(of: id) == .cancelled)
}

// MARK: - Confirmation decisions

@Test("approving a confirmation runs the command to success")
func approvingConfirmationRuns() throws {
    let bus = makeBus(.confirmThenSucceed)
    let recorder = EventRecorder()
    bus.subscribe { recorder.record($0) }

    let id = "cmd_00000000000000000000dddd"
    _ = try bus.submit(makeEnvelope(id: id))
    let decided = bus.decideConfirmation(commandId: id, approved: true)

    #expect(decided?.status == .succeeded)
    #expect(recorder.statuses == [.received, .planned, .requiresConfirmation, .running, .succeeded])
}

@Test("denying a confirmation cancels the command")
func denyingConfirmationCancels() throws {
    let bus = makeBus(.confirmThenSucceed)
    let id = "cmd_00000000000000000000eeee"
    _ = try bus.submit(makeEnvelope(id: id))
    let decided = bus.decideConfirmation(commandId: id, approved: false)

    #expect(decided?.status == .cancelled)
    #expect(bus.status(of: id) == .cancelled)
}

// MARK: - Execution mapping and source gating

@Test("an unavailable tool ends as a failed command with an unavailable category")
func unavailableMapsToFailed() throws {
    let bus = makeBus(.unavailable)
    let id = "cmd_00000000000000000000ffff"
    let receipt = try bus.submit(makeEnvelope(id: id))

    #expect(receipt.status == .failed)
    #expect(bus.events(of: id).last?.error?.category == .unavailableCapability)
}

@Test("reserved sources are rejected before any command state is created")
func reservedSourcesAreRejected() {
    let bus = makeBus(.succeed)

    for source in [CommandSource.voice, .ios, .agent] {
        let envelope = makeEnvelope(source: source, id: "cmd_0000000000000000000reserved")
        #expect(throws: SubmissionError.reservedSource(source)) {
            try bus.submit(envelope)
        }
    }
    // No state was created for the rejected command.
    #expect(bus.status(of: "cmd_0000000000000000000reserved") == nil)
}

@Test("production sources are accepted")
func productionSourcesAreAccepted() throws {
    let bus = makeBus(.succeed)
    for (index, source) in [CommandSource.dashboard, .hotkey, .cli, .automation, .system].enumerated() {
        let id = "cmd_000000000000000000prod\(index)"
        let receipt = try bus.submit(makeEnvelope(source: source, id: id))
        #expect(receipt.status == .succeeded)
    }
}
