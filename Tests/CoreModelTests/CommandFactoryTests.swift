import Foundation
import Testing

import CerebralContracts
import CerebralCore
import CerebralShared

/// AC-22.2: clock and ID generation are injectable and deterministic.

@Test("the factory mints identifiers and timestamps from injected dependencies")
func factoryUsesInjectedClockAndIdentifiers() {
    let instant = Date(timeIntervalSinceReferenceDate: 0)
    let clock = FixedClock(instant, step: 1)
    let identifiers = SequentialIdentifierGenerator(start: 1)
    let factory = CommandFactory(clock: clock, identifiers: identifiers)

    let envelope = factory.makeEnvelope(
        source: .cli,
        rawInput: "mode developer",
        privacy: CommandPrivacy(cloudPolicy: .deny, sensitivity: .sensitivityPrivate)
    )

    #expect(envelope.id == "cmd_00000001")
    #expect(CommandIdentity.isValidCommandIdentifier(envelope.id))
    #expect(envelope.timestamp == instant)
    #expect(envelope.source == .cli)
    #expect(envelope.schemaVersion == CommandContract.schemaVersion)

    let event = factory.makeLifecycleEvent(
        commandId: envelope.id,
        previousStatus: nil,
        currentStatus: .received,
        message: "Command received."
    )

    #expect(event.id == "evt_00000002")
    #expect(CommandIdentity.isValidEventIdentifier(event.id))
    #expect(event.timestamp == instant.addingTimeInterval(1))
    #expect(event.commandID == envelope.id)
    #expect(event.previousStatus == nil)
    #expect(event.currentStatus == .received)

    let result = factory.makeTerminalResult(
        commandId: envelope.id,
        status: .succeeded,
        summary: "Developer mode plan completed."
    )

    #expect(result.commandID == envelope.id)
    #expect(result.status == .succeeded)
    #expect(result.completedAt == instant.addingTimeInterval(2))
}

@Test("the UUID generator produces contract-valid identifiers")
func uuidGeneratorProducesValidIdentifiers() {
    let generator = UUIDIdentifierGenerator()
    #expect(CommandIdentity.isValidCommandIdentifier(generator.nextIdentifier(for: .command)))
    #expect(CommandIdentity.isValidEventIdentifier(generator.nextIdentifier(for: .event)))
    #expect(CommandIdentity.isValidCorrelationIdentifier(generator.nextIdentifier(for: .correlation)))
}

@Test("identifier validation rejects malformed identifiers")
func identifierValidationRejectsBadInput() {
    #expect(!CommandIdentity.isValidCommandIdentifier("cmd_short"))      // 5-char suffix
    #expect(!CommandIdentity.isValidCommandIdentifier("evt_00000001"))   // wrong prefix
    #expect(!CommandIdentity.isValidCommandIdentifier("cmd_has space!")) // illegal characters
    #expect(CommandIdentity.isValidCorrelationIdentifier("corr_00000001"))
}
