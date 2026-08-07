import Foundation
import Testing

import CerebralContracts
import CerebralCore
import CerebralTools

/// NIC-127 Increment 3: the portable `web.open` handler validates its I/O against the contract and
/// translates native-capability errors into structured tool errors. The scheme/host validation and
/// Chrome preference are the adapter's job (covered in MacAdapterTests).

@Test("web.open echoes the url and reports opened on success")
func webOpenHandlerHappyPath() async throws {
    let handler = WebOpenHandler(capability: MockWebOpenCapability(matrix: .allAvailable))
    let output = try await handler.execute(input: Data(#"{"url":"https://example.com/a"}"#.utf8))
    let decoded = try CerebralHelmWebOpenOutput(data: output)
    #expect(decoded.url == "https://example.com/a")
    #expect(decoded.opened)
}

@Test("web.open rejects malformed input as invalidInput before the adapter runs")
func webOpenHandlerRejectsMalformedInput() async throws {
    let handler = WebOpenHandler(capability: MockWebOpenCapability(matrix: .allAvailable))
    do {
        _ = try await handler.execute(input: Data(#"{"url":123}"#.utf8))
    } catch ToolHandlerError.invalidInput {
        return
    }
    Issue.record("a non-string url must be rejected as invalid input")
}

@Test("web.open with the capability unavailable is a structured unavailable, never a fake success")
func webOpenHandlerUnavailable() async throws {
    let handler = WebOpenHandler(capability: MockWebOpenCapability(matrix: .none))
    do {
        _ = try await handler.execute(input: Data(#"{"url":"https://example.com/a"}"#.utf8))
    } catch ToolHandlerError.unavailable {
        return
    }
    Issue.record("an unavailable capability must surface as ToolHandlerError.unavailable")
}
