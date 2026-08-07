import Foundation
import Testing

import CerebralContracts
import CerebralCore
import CerebralTools

/// Quick actions phase 4: the portable `messages.send` handler. Injection safety, the AppleScript
/// and the two permission grants are the adapter's job.
///
/// The descriptor takes `allow_external_write_when_user_authored` (owner decision, 2026-08-04):
/// filling in a recipient and a message and pressing Send *is* the human's confirmation, while an
/// agent proposing the same call still gates. `ToolRegistryTests` holds the descriptor to that.

@Test("messages.send reports sent only when the adapter confirmed it")
func messagesSendHappyPath() async throws {
    let handler = MessagesSendHandler(capability: MockMessagingCapability(matrix: .allAvailable))
    let input = #"{"messageBody":"Running late","messageTarget":"+15551234567","messageTargetKind":"participant","messageTargetName":"Jamie"}"#
    let output = try await handler.execute(input: Data(input.utf8))
    let decoded = try CerebralHelmMessagesSendOutput(data: output)
    #expect(decoded.messageSent)
    #expect(decoded.messageTargetName == "Jamie")
}

@Test("messages.send rejects an empty message and a missing recipient before the adapter runs")
func messagesSendRejectsIncomplete() async throws {
    let handler = MessagesSendHandler(capability: MockMessagingCapability(matrix: .allAvailable))
    for bad in [
        #"{"messageTarget":"+1555","messageTargetKind":"participant"}"#,
        #"{"messageBody":"Hi","messageTargetKind":"participant"}"#,
        #"{"messageBody":"Hi","messageTarget":"+1555"}"#
    ] {
        do {
            _ = try await handler.execute(input: Data(bad.utf8))
            Issue.record("incomplete input must be rejected: \(bad)")
        } catch ToolHandlerError.invalidInput {
            continue
        }
    }
}

@Test("an unknown target kind is refused by the contract, not passed through")
func messagesSendRefusesUnknownKind() async throws {
    // The enum is the gate: "everyone" is not a target kind, and the tool never sees it.
    let handler = MessagesSendHandler(capability: MockMessagingCapability(matrix: .allAvailable))
    do {
        _ = try await handler.execute(
            input: Data(#"{"messageBody":"Hi","messageTarget":"x","messageTargetKind":"everyone"}"#.utf8)
        )
    } catch ToolHandlerError.invalidInput {
        return
    }
    Issue.record("an unknown target kind must be rejected as invalid input")
}

@Test("messages.send with the capability unavailable never reports a fake send")
func messagesSendUnavailable() async throws {
    let handler = MessagesSendHandler(capability: MockMessagingCapability(matrix: .none))
    do {
        _ = try await handler.execute(
            input: Data(#"{"messageBody":"Hi","messageTarget":"x","messageTargetKind":"participant"}"#.utf8)
        )
    } catch ToolHandlerError.unavailable {
        return
    }
    Issue.record("an unavailable capability must surface as ToolHandlerError.unavailable")
}
