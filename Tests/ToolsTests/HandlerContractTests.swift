import Foundation
import Testing

import CerebralAdapterContractSuite
import CerebralContracts
import CerebralCore
import CerebralTools

/// NIC-33-A (PRE-SAFETY-6): portable read and local-write tool handlers.
///
/// AC-33.1 every tool validates I/O; AC-33.3 all handlers satisfy the shared
/// contract suite. The contract cases themselves live in
/// `CerebralAdapterContractSuite` (FR-TOL-04) so the identical checks run against
/// the native adapters on the Mac (MAC-ADAPTER-6); this file is the thin runner
/// binding them to the mock composition. The cases exercise each bound handler
/// directly so they are phase-independent — covering Mac-only tools that the
/// pre-Mac executor refuses via the NIC-111 availability gate. Capability and
/// permission paths still run through the executor below.

private func descriptorsDirectory() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // ToolsTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // repository root
        .appendingPathComponent("packages/contracts/fixtures/valid/tools/descriptors", isDirectory: true)
}

private func mockRegistry() throws -> ToolRegistry {
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
    ], entries: [
        // The same fixture note as a library entry, so note.list/note.read have
        // something deterministic to answer with (NIC-162).
        NoteListEntry(
            path: "inbox/ch-idea-001.md",
            title: "Fixture note",
            noteID: "ch-idea-001",
            folder: "inbox",
            project: nil,
            sensitivity: "private",
            updated: "2026-06-23"
        ),
    ], bodies: ["inbox/ch-idea-001.md": "Deterministic body."])
    return try PreMacToolRuntime.makeRegistry(
        descriptorsDirectory: descriptorsDirectory(),
        capabilities: MockContractComposition.bundle(),
        knowledge: knowledge,
        hookCatalog: HookCatalog([MockContractComposition.fixtures.hookID: MockContractComposition.hookInvocation])
    )
}

@Test("every portable handler satisfies the shared tool contract suite (AC-33.1, AC-33.3)")
func portableHandlersSatisfyContractSuite() async throws {
    let cases = AdapterContractSuite.handlerCases(
        registry: try mockRegistry(),
        fixtures: MockContractComposition.fixtures
    )
    #expect(cases.count == 11)
    await runContractCases(cases)
}

@Test("a disabled native capability yields an unavailable result (FR-SHL-06)")
func disabledCapabilityIsUnavailable() async throws {
    let executor = try PreMacToolRuntime.makeExecutor(descriptorsDirectory: descriptorsDirectory(), capabilities: .mocks(matrix: .none))
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

@Test("note.list and note.read run read-only, without confirmation (NIC-162)")
func noteLibraryToolsRunWithoutConfirmation() async throws {
    let descriptors = try ToolDescriptorCatalog.loadDescriptors(directory: descriptorsDirectory())
    for id in ["note.list", "note.read"] {
        let descriptor = try #require(descriptors.first { $0.id == id })
        #expect(descriptor.risk == .readOnly)
        #expect(descriptor.confirmationPolicyKey == .allowReadWithoutConfirmation)
        // Reading notes is the user's own files; it needs no macOS permission
        // beyond reaching the root, and both phases can do it.
        #expect(descriptor.requiredPermissions == ["knowledge_root_read"])
        #expect(descriptor.availability.preMAC && descriptor.availability.macOS)
    }
}

@Test("an unavailable knowledge root makes the note reads unavailable, never empty (NIC-162)")
func missingKnowledgeRootIsUnavailableNotEmpty() async throws {
    let knowledge = MockKnowledgeService(rootState: .missing)
    let executor = try PreMacToolRuntime.makeExecutor(descriptorsDirectory: descriptorsDirectory(), knowledge: knowledge)

    let listed = await executor.execute(ToolInvocation(toolID: "note.list", input: Data("{}".utf8)))
    #expect(listed.status == .unavailable)
    #expect(listed.error?.category == .unavailableCapability)

    let read = await executor.execute(
        ToolInvocation(toolID: "note.read", input: Data(#"{"path":"inbox/ch-idea-001.md"}"#.utf8))
    )
    #expect(read.status == .unavailable)
}

@Test("note.read rejects input that does not match its contract before touching the service")
func noteReadRejectsMalformedInput() async throws {
    let handler = NoteReadHandler(knowledge: MockKnowledgeService())
    for malformed in [#"{}"#, #"{"path":42}"#] {
        await #expect(throws: ToolHandlerError.self) {
            _ = try await handler.execute(input: Data(malformed.utf8))
        }
    }
}

@Test("apps.list maps discovery results into contract-valid output (NIC-119)")
func appsListHandlerMapsOutput() async throws {
    let handler = AppsListHandler(capability: MockAppDiscoveryCapability())
    let output = try await handler.execute(input: Data("{}".utf8))
    let decoded = try CerebralHelmAppsListOutput(data: output)
    #expect(decoded.apps.map(\.name) == ["Safari", "Mail", "Notes"])
    #expect(decoded.apps.map(\.bundleID) == ["com.apple.Safari", "com.apple.mail", "com.apple.Notes"])
    #expect(decoded.truncated == false)
}

@Test("apps.list with the capability unavailable is a structured unavailable, never a mock success")
func appsListUnavailableIsStructured() async throws {
    let handler = AppsListHandler(capability: MockAppDiscoveryCapability(matrix: .none))
    await #expect(throws: ToolHandlerError.self) {
        _ = try await handler.execute(input: Data("{}".utf8))
    }
}

@Test("apps.quitall quits the running apps and reports them (NIC-143)")
func appsQuitAllQuitsRunning() async throws {
    let handler = AppsQuitAllHandler(capability: MockApplicationLifecycleCapability(
        runningBundleIDs: ["com.apple.Safari", "com.microsoft.VSCode"]
    ))
    let output = try await handler.execute(input: Data("{}".utf8))
    let decoded = try CerebralHelmAppsQuitAllOutput(data: output)
    #expect(decoded.status == .quit)
    #expect(decoded.bundleIDS == ["com.apple.Safari", "com.microsoft.VSCode"])
}

@Test("apps.quitall on an empty desktop reports 'none' with no ids (NIC-143)")
func appsQuitAllEmptyIsNone() async throws {
    let handler = AppsQuitAllHandler(capability: MockApplicationLifecycleCapability(runningBundleIDs: []))
    let output = try await handler.execute(input: Data("{}".utf8))
    let decoded = try CerebralHelmAppsQuitAllOutput(data: output)
    #expect(decoded.status == .none)
    #expect(decoded.bundleIDS.isEmpty)
}

@Test("apps.quitall with the capability unavailable is a structured unavailable, never a mock success")
func appsQuitAllUnavailableIsStructured() async throws {
    let handler = AppsQuitAllHandler(capability: MockApplicationLifecycleCapability(matrix: .none))
    await #expect(throws: ToolHandlerError.self) {
        _ = try await handler.execute(input: Data("{}".utf8))
    }
}
