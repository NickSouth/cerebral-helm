import Foundation
import Testing

import CerebralContracts
import CerebralCore
import CerebralTools

/// NIC-131 Increment 4: the portable `project.open` handler validates its I/O against the
/// contract and translates native-capability errors into structured tool errors. The
/// path-to-projects-root constraint is the adapter's job (covered in MacAdapterTests).

@Test("project.open echoes the repo path and reports opened on success")
func projectOpenHandlerHappyPath() async throws {
    let handler = ProjectOpenHandler(capability: MockProjectCapability(matrix: .allAvailable))
    let output = try await handler.execute(input: Data(#"{"repoPath":"/Users/x/Projects/demo"}"#.utf8))
    let decoded = try CerebralHelmProjectOpenOutput(data: output)
    #expect(decoded.repoPath == "/Users/x/Projects/demo")
    #expect(decoded.opened)
}

@Test("project.open rejects malformed input as invalidInput before the adapter runs")
func projectOpenHandlerRejectsMalformedInput() async throws {
    let handler = ProjectOpenHandler(capability: MockProjectCapability(matrix: .allAvailable))
    do {
        _ = try await handler.execute(input: Data(#"{"repoPath":123}"#.utf8))
    } catch ToolHandlerError.invalidInput {
        return
    }
    Issue.record("a non-string repoPath must be rejected as invalid input")
}

@Test("project.open with the capability unavailable is a structured unavailable, never a fake success")
func projectOpenHandlerUnavailable() async throws {
    let handler = ProjectOpenHandler(capability: MockProjectCapability(matrix: .none))
    do {
        _ = try await handler.execute(input: Data(#"{"repoPath":"/Users/x/Projects/demo"}"#.utf8))
    } catch ToolHandlerError.unavailable {
        return
    }
    Issue.record("an unavailable capability must surface as ToolHandlerError.unavailable")
}
