import Foundation
import Testing

import CerebralContracts
import CerebralCore
import CerebralTools

/// Quick actions phase 4, action 3: the portable `linear.createissue` handler validates its I/O
/// against the contract and translates native-capability errors into structured tool errors. The
/// GraphQL transport, the header format and the Keychain read are the adapter's job.

@Test("linear.createissue returns the identifier and URL Linear assigned")
func linearCreateIssueHappyPath() async throws {
    let handler = LinearCreateIssueHandler(capability: MockLinearIssueCapability(matrix: .allAvailable))
    let input = #"{"issueTitle":"Apps aren't visible","linearTeamID":"team-1","linearLabelIDs":["l1","l2"],"issuePriority":2}"#
    let output = try await handler.execute(input: Data(input.utf8))
    let decoded = try CerebralHelmLinearCreateIssueOutput(data: output)
    #expect(decoded.issueIdentifier == "MOCK-1")
    #expect(decoded.issueURL.contains("linear.app"))
}

@Test("linear.createissue requires a team — it is never inferred")
func linearCreateIssueRequiresTeam() async throws {
    // A workspace can have several teams; guessing one would file the ticket somewhere the user
    // did not choose, so the contract makes it required rather than optional-with-a-default.
    let handler = LinearCreateIssueHandler(capability: MockLinearIssueCapability(matrix: .allAvailable))
    do {
        _ = try await handler.execute(input: Data(#"{"issueTitle":"No team"}"#.utf8))
    } catch ToolHandlerError.invalidInput {
        return
    }
    Issue.record("input with no team must be rejected as invalid input")
}

@Test("linear.createissue with the capability unavailable never reports a fake success")
func linearCreateIssueUnavailable() async throws {
    let handler = LinearCreateIssueHandler(capability: MockLinearIssueCapability(matrix: .none))
    do {
        _ = try await handler.execute(input: Data(#"{"issueTitle":"x","linearTeamID":"t"}"#.utf8))
    } catch ToolHandlerError.unavailable {
        return
    }
    Issue.record("an unavailable capability must surface as ToolHandlerError.unavailable")
}
