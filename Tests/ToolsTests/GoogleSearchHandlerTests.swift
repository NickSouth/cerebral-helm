import Foundation
import Testing

import CerebralContracts
import CerebralCore
import CerebralTools

/// NIC-134 Increment 6: the portable `google.search` handler validates its I/O against the
/// contract and translates native-capability errors into structured tool errors. The host-fixed
/// URL construction and Chrome preference are the adapter's job (covered in MacAdapterTests).

@Test("google.search echoes the query and reports opened on success")
func googleSearchHandlerHappyPath() async throws {
    let handler = GoogleSearchHandler(capability: MockGoogleSearchCapability(matrix: .allAvailable))
    let output = try await handler.execute(input: Data(#"{"query":"where to watch Dune"}"#.utf8))
    let decoded = try CerebralHelmGoogleSearchOutput(data: output)
    #expect(decoded.query == "where to watch Dune")
    #expect(decoded.opened)
    #expect(decoded.resolvedURL.contains("google.com"))
}

@Test("google.search rejects malformed input as invalidInput before the adapter runs")
func googleSearchHandlerRejectsMalformedInput() async throws {
    let handler = GoogleSearchHandler(capability: MockGoogleSearchCapability(matrix: .allAvailable))
    do {
        _ = try await handler.execute(input: Data(#"{"query":123}"#.utf8))
    } catch ToolHandlerError.invalidInput {
        return
    }
    Issue.record("a non-string query must be rejected as invalid input")
}

@Test("google.search with the capability unavailable is a structured unavailable, never a fake success")
func googleSearchHandlerUnavailable() async throws {
    let handler = GoogleSearchHandler(capability: MockGoogleSearchCapability(matrix: .none))
    do {
        _ = try await handler.execute(input: Data(#"{"query":"anything"}"#.utf8))
    } catch ToolHandlerError.unavailable {
        return
    }
    Issue.record("an unavailable capability must surface as ToolHandlerError.unavailable")
}
