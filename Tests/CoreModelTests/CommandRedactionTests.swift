import Foundation
import Testing

import CerebralCore
import CerebralShared

/// AC-22.3: sensitive fields are identifiable for redaction.

private func makeEnvelope(sensitivity: CommandSensitivity) -> CommandEnvelope {
    let factory = CommandFactory(
        clock: FixedClock(Date(timeIntervalSinceReferenceDate: 0)),
        identifiers: SequentialIdentifierGenerator()
    )
    return factory.makeEnvelope(
        source: .cli,
        rawInput: "note capture private thought",
        privacy: CommandPrivacy(cloudPolicy: .deny, sensitivity: sensitivity)
    )
}

@Test("public commands expose no sensitive fields")
func publicCommandsHaveNoSensitiveFields() {
    let envelope = makeEnvelope(sensitivity: .sensitivityPublic)
    #expect(CommandRedaction.sensitiveFieldPaths(for: envelope).isEmpty)
    #expect(!CommandRedaction.isSensitive(envelope))
}

@Test("private commands mark the payload sensitive but not raw input")
func privateCommandsRedactPayload() {
    let envelope = makeEnvelope(sensitivity: .sensitivityPrivate)
    #expect(CommandRedaction.sensitiveFieldPaths(for: envelope) == ["payload"])
    #expect(CommandRedaction.isSensitive(envelope))
}

@Test("sensitive and secret commands mark raw input and payload sensitive")
func sensitiveCommandsRedactRawInputAndPayload() {
    for sensitivity in [CommandSensitivity.sensitive, .secret] {
        let envelope = makeEnvelope(sensitivity: sensitivity)
        let paths = CommandRedaction.sensitiveFieldPaths(for: envelope)
        #expect(paths.contains("rawInput"))
        #expect(paths.contains("payload"))
    }
}
