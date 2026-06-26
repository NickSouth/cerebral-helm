import Foundation
import Testing

import CerebralContracts
import CerebralCore
import CerebralShared

/// NIC-23: lifecycle state machine and ordered event publication.

private func makeMachine() -> CommandLifecycleMachine {
    let factory = CommandFactory(
        clock: FixedClock(Date(timeIntervalSinceReferenceDate: 0), step: 1),
        identifiers: SequentialIdentifierGenerator()
    )
    return CommandLifecycleMachine(commandId: "cmd_00000000000000000000aaaa", factory: factory)
}

private func receivedMachine() throws -> CommandLifecycleMachine {
    var machine = makeMachine()
    try machine.markReceived()
    return machine
}

/// The canonical allowed edge set, mirroring the schema `oneOf`. Used as a
/// drift guard against ``CommandLifecycle/isValidTransition(from:to:)``.
private let allowedEdges: Set<[String]> = [
    ["none", "received"],
    ["received", "planned"],
    ["planned", "requires_confirmation"],
    ["planned", "running"],
    ["requires_confirmation", "running"],
    ["requires_confirmation", "cancelled"],
    ["running", "succeeded"],
    ["running", "failed"],
    ["running", "cancelled"],
]

// MARK: - AC-23.1 allowed paths

@Test("a full planned-to-succeeded path passes and chains previous statuses")
func happyPathSucceeds() throws {
    var machine = makeMachine()
    try machine.markReceived(message: "Command received.")
    try machine.markPlanned()
    try machine.markRunning()
    let terminal = try machine.markSucceeded(message: "Done.")

    #expect(machine.status == .succeeded)
    #expect(machine.isTerminal)
    #expect(machine.events.count == 4)
    #expect(machine.events.map(\.currentStatus) == [.received, .planned, .running, .succeeded])
    #expect(machine.events.map(\.previousStatus) == [nil, .received, .planned, .running])
    // Deterministic identifiers/timestamps from the injected factory.
    #expect(machine.events.map(\.id) == ["evt_00000001", "evt_00000002", "evt_00000003", "evt_00000004"])
    #expect(terminal.currentStatus == .succeeded)
}

@Test("the confirmation-then-run path passes")
func confirmationThenRunPasses() throws {
    var machine = try receivedMachine()
    try machine.markPlanned()
    try machine.requireConfirmation()
    try machine.markRunning()
    try machine.markSucceeded()

    #expect(machine.events.map(\.currentStatus) == [.received, .planned, .requiresConfirmation, .running, .succeeded])
}

@Test("running can fail or be cancelled")
func runningTerminalVariants() throws {
    var failing = try receivedMachine()
    try failing.markPlanned()
    try failing.markRunning()
    let failure = CerebralHelmCommandLifecycleEventError(
        category: .internalFailure, code: "x", details: nil, message: "boom", remediation: nil
    )
    try failing.markFailed(error: failure)
    #expect(failing.status == .failed)
    #expect(failing.events.last?.error?.category == .internalFailure)

    var cancelling = try receivedMachine()
    try cancelling.markPlanned()
    try cancelling.markRunning()
    try cancelling.cancel()
    #expect(cancelling.status == .cancelled)
}

// MARK: - AC-23.3 denied confirmation becomes cancelled

@Test("a denied confirmation ends as cancelled, not failed")
func deniedConfirmationCancels() throws {
    var machine = try receivedMachine()
    try machine.markPlanned()
    try machine.requireConfirmation()
    let event = try machine.denyConfirmation()

    #expect(event.previousStatus == .requiresConfirmation)
    #expect(event.currentStatus == .cancelled)
    #expect(machine.status == .cancelled)
    #expect(machine.status != .failed)
}

// MARK: - AC-23.2 invalid paths fail deterministically

@Test("skipping a stage is rejected with a deterministic error")
func skippingStageIsRejected() {
    #expect(throws: LifecycleTransitionError.invalidTransition(from: .received, to: .running)) {
        var machine = try receivedMachine()
        try machine.transition(to: .running)
    }
}

@Test("entering anywhere but received is rejected")
func mustEnterAtReceived() {
    #expect(throws: LifecycleTransitionError.invalidTransition(from: nil, to: .planned)) {
        var machine = makeMachine()
        try machine.transition(to: .planned)
    }
}

@Test("a terminal command is immutable")
func terminalCommandIsImmutable() throws {
    var machine = try receivedMachine()
    try machine.markPlanned()
    try machine.markRunning()
    try machine.markSucceeded()

    #expect(throws: LifecycleTransitionError.terminalCommand(status: .succeeded, attempted: .cancelled)) {
        var terminal = machine
        try terminal.cancel()
    }
    // The rejected transition left state and the event log unchanged.
    #expect(machine.events.count == 4)
    #expect(machine.status == .succeeded)
}

@Test("rejected transitions emit an invalid_transition structured error")
func rejectionMapsToStructuredError() {
    let error = LifecycleTransitionError.invalidTransition(from: .planned, to: .succeeded)
    #expect(error.structuredError.category == .invalidTransition)
    #expect(error.structuredError.code == "lifecycle.invalid_transition")
}

// MARK: - Drift guard

@Test("isValidTransition matches the canonical schema edge set exactly")
func transitionRulesMatchSchema() {
    let candidates: [CommandStatus?] = [nil] + CommandLifecycle.allStatuses
    for previous in candidates {
        for next in CommandLifecycle.allStatuses {
            let edge = [previous?.rawValue ?? "none", next.rawValue]
            let expected = allowedEdges.contains(edge)
            #expect(
                CommandLifecycle.isValidTransition(from: previous, to: next) == expected,
                "edge \(edge) expected \(expected)"
            )
        }
    }
}
