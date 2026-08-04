import Foundation
import Testing

import CerebralContracts
import CerebralCore
import CerebralTools

/// Quick actions phase 4: the portable `project.scaffold` handler validates its I/O and translates
/// native-capability errors. Containment, naming and the descriptor body are the adapter's job.

@Test("project.scaffold returns both the folder and the descriptor it wrote")
func projectScaffoldHappyPath() async throws {
    let handler = ProjectScaffoldHandler(capability: MockProjectScaffoldCapability(matrix: .allAvailable))
    let output = try await handler.execute(input: Data(#"{"projectName":"Helm Companion"}"#.utf8))
    let decoded = try CerebralHelmProjectScaffoldOutput(data: output)
    #expect(decoded.projectPath.hasSuffix("Helm Companion"))
    #expect(decoded.projectDescriptorPath.hasSuffix("PROJECT.md"))
}

@Test("project.scaffold rejects a nameless project before the adapter runs")
func projectScaffoldRequiresName() async throws {
    let handler = ProjectScaffoldHandler(capability: MockProjectScaffoldCapability(matrix: .allAvailable))
    do {
        _ = try await handler.execute(input: Data(#"{"projectImportance":5}"#.utf8))
    } catch ToolHandlerError.invalidInput {
        return
    }
    Issue.record("input with no name must be rejected as invalid input")
}

@Test("project.scaffold with the capability unavailable never reports a fake success")
func projectScaffoldUnavailable() async throws {
    let handler = ProjectScaffoldHandler(capability: MockProjectScaffoldCapability(matrix: .none))
    do {
        _ = try await handler.execute(input: Data(#"{"projectName":"x"}"#.utf8))
    } catch ToolHandlerError.unavailable {
        return
    }
    Issue.record("an unavailable capability must surface as ToolHandlerError.unavailable")
}
