import Foundation
import Testing

import CerebralContracts
import CerebralCore
import CerebralTools

/// NIC-33-A (PRE-SAFETY-6): portable read and local-write tool handlers.
///
/// AC-33.1 every tool validates I/O; AC-33.3 all handlers satisfy the shared
/// contract suite. The suite runs each handler end to end through the registry,
/// policy engine, and executor — the same suite a native adapter will later
/// satisfy (MAC-ADAPTER-6).

private func descriptorsDirectory() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // ToolsTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // repository root
        .appendingPathComponent("packages/contracts/fixtures/valid/tools/descriptors", isDirectory: true)
}

private struct ToolContractCase: Sendable {
    let toolID: String
    let input: Data
    let validateOutput: @Sendable (Data) throws -> Void
}

private func runContractCase(_ contractCase: ToolContractCase, knowledge: any KnowledgeService) async throws {
    let executor = try PreMacToolRuntime.makeExecutor(descriptorsDirectory: descriptorsDirectory(), knowledge: knowledge)
    let result = await executor.execute(ToolInvocation(toolID: contractCase.toolID, input: contractCase.input))

    #expect(result.status == .success, "\(contractCase.toolID): \(result.error?.message ?? "no error")")
    let output = try #require(result.output)
    try contractCase.validateOutput(output)
}

@Test("every portable handler satisfies the shared tool contract suite (AC-33.1, AC-33.3)")
func portableHandlersSatisfyContractSuite() async throws {
    let knowledge = MockKnowledgeService(hits: [
        NoteSearchHit(
            noteID: "ch-idea-001",
            title: "Fixture note",
            excerpt: "Deterministic body.",
            path: "inbox/ch-idea-001.md",
            updated: "2026-06-23",
            sensitivity: "private",
            freshness: "fresh"
        ),
    ])

    let cases: [ToolContractCase] = [
        ToolContractCase(toolID: "app.open", input: Data(#"{"appId":"vscode"}"#.utf8)) { output in
            let decoded = try CerebralHelmAppOpenOutput(data: output)
            #expect(decoded.appID == "vscode")
            #expect(decoded.launched)
        },
        ToolContractCase(toolID: "url.open", input: Data(#"{"urlId":"github"}"#.utf8)) { output in
            let decoded = try CerebralHelmURLOpenOutput(data: output)
            #expect(decoded.urlID == "github")
            #expect(decoded.opened)
        },
        ToolContractCase(toolID: "system.status.read", input: Data(#"{"metrics":["cpu","memory"]}"#.utf8)) { output in
            let decoded = try CerebralHelmSystemStatusReadOutput(data: output)
            #expect(decoded.metrics.count == 2)
        },
        ToolContractCase(toolID: "note.capture", input: Data(#"{"title":"t","body":"b","kind":"idea"}"#.utf8)) { output in
            let decoded = try CerebralHelmNoteCaptureOutput(data: output)
            #expect(decoded.created)
            #expect(decoded.noteID == "ch-idea-001")
        },
        ToolContractCase(toolID: "note.search", input: Data(#"{"query":"fixture"}"#.utf8)) { output in
            let decoded = try CerebralHelmNoteSearchOutput(data: output)
            #expect(decoded.results.count == 1)
        },
    ]

    for contractCase in cases {
        try await runContractCase(contractCase, knowledge: knowledge)
    }
}

@Test("invalid input is rejected before the adapter (AC-33.1)")
func invalidInputIsRejected() async throws {
    let executor = try PreMacToolRuntime.makeExecutor(descriptorsDirectory: descriptorsDirectory())
    // appId must be a string.
    let result = await executor.execute(ToolInvocation(toolID: "app.open", input: Data(#"{"appId":123}"#.utf8)))

    #expect(result.status == .failure)
    #expect(result.error?.category == .invalidInput)
}

@Test("a disabled native capability yields an unavailable result (FR-SHL-06)")
func disabledCapabilityIsUnavailable() async throws {
    let executor = try PreMacToolRuntime.makeExecutor(descriptorsDirectory: descriptorsDirectory(), capabilityMatrix: .none)
    let result = await executor.execute(ToolInvocation(toolID: "system.status.read", input: Data("{}".utf8)))

    #expect(result.status == .unavailable)
    #expect(result.error?.category == .unavailableCapability)
}

@Test("a read-only knowledge root denies note capture")
func readOnlyKnowledgeRootDeniesCapture() async throws {
    let knowledge = MockKnowledgeService(rootState: .readOnly)
    let executor = try PreMacToolRuntime.makeExecutor(descriptorsDirectory: descriptorsDirectory(), knowledge: knowledge)
    let result = await executor.execute(ToolInvocation(toolID: "note.capture", input: Data(#"{"title":"t","body":"b","kind":"idea"}"#.utf8)))

    #expect(result.status == .denied)
    #expect(result.error?.category == .permissionDenied)
}
