import Foundation
import Testing

import CerebralContracts
import CerebralCore
import CerebralShared
import CerebralTools

/// NIC-110: descriptor-declared redaction is enforced on the confirmation
/// disclosure / ConfirmationPlan, not just the tool-call log. A value the
/// descriptor marks as a redaction path (e.g. note.search `/query`,
/// note.capture `/body`, hook.run `/environment`) must never reach the
/// disclosure's `actionSummary` or any argument value in the clear — the
/// runtime masks it before makePlan/PlanHash run.

private func descriptorsDirectory() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // ToolsTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // repository root
        .appendingPathComponent("packages/contracts/fixtures/valid/tools/descriptors", isDirectory: true)
}

/// A runtime whose policy forces confirmation for every risk class, so even a
/// read-only intent (note.search) produces a disclosure we can inspect.
private func makeConfirmingRuntime(
    knowledge: any KnowledgeService = MockKnowledgeService(),
    hookEnvironment: [String: String] = ["CI": "true"]
) throws -> CommandRuntime {
    let hookInvocation = HookInvocation(
        executable: "/usr/bin/just",
        arguments: ["build"],
        workingDirectory: "/repo",
        environment: hookEnvironment
    )
    let hookCatalog = HookCatalog(["ondraft-dev": hookInvocation])
    let registry = try PreMacToolRuntime.makeRegistry(
        descriptorsDirectory: descriptorsDirectory(),
        knowledge: knowledge,
        hookCatalog: hookCatalog
    )
    let references = CommandReferences(
        apps: [ReferenceEntry(id: "vscode", label: "VS Code", target: "com.microsoft.VSCode")],
        urls: [ReferenceEntry(id: "github", label: "GitHub", target: "https://github.com")],
        hooks: [ReferenceEntry(id: "ondraft-dev", label: "On Draft Dev", target: "/scripts/ondraft.sh")],
        modeIds: ["developer"]
    )
    let factory = CommandFactory(
        clock: FixedClock(Date(timeIntervalSinceReferenceDate: 0), step: 1),
        identifiers: SequentialIdentifierGenerator()
    )
    let coordinator = ConfirmationCoordinator(
        clock: FixedClock(Date(timeIntervalSinceReferenceDate: 0)),
        identifiers: SequentialIdentifierGenerator()
    )
    // Every risk class to require confirmation, so read-only and local-write
    // intents also pause and surface a disclosure to inspect.
    let policy = PolicyEngine(
        overrides: PolicyOverrides(minimumDecisions: [
            .readOnly: .requireConfirmation,
            .localWrite: .requireConfirmation,
        ])
    )
    return CommandRuntime(
        registry: registry,
        policy: policy,
        coordinator: coordinator,
        factory: factory,
        references: references,
        hookCatalog: hookCatalog,
        modePlanner: StubModePlanner()
    )
}

/// Joins a disclosure's free text (action summary plus every argument value)
/// into one haystack — the surfaces a descriptor-covered value must never reach.
private func disclosureText(_ disclosure: CerebralHelmConfirmationDisclosure) -> String {
    ([disclosure.actionSummary] + disclosure.arguments.map(\.value)).joined(separator: "\u{1f}")
}

@Test("the note.search disclosure shows the redaction marker, not the raw query (NIC-110)")
func noteSearchDisclosureMasksQuery() async throws {
    let canary = "CANARY-acme-merger-q3"
    let runtime = try makeConfirmingRuntime()

    let pending = await runtime.submit("search \(canary)", source: .cli)
    guard case let .awaitingConfirmation(_, disclosure, _) = pending else {
        Issue.record("Expected awaitingConfirmation, got \(pending)"); return
    }
    #expect(disclosure.tool.id == "note.search")
    // The raw query never appears; the descriptor-covered value is masked.
    #expect(!disclosureText(disclosure).contains(canary))
    #expect(disclosure.actionSummary.contains(SchemaRedactor.marker))
    #expect(disclosure.actionSummary == "Search notes for \(SchemaRedactor.marker).")
}

@Test("no disclosure leaks any descriptor-covered value through summary or arguments (NIC-110)")
func everyDisclosureRedactsCoveredValues() async throws {
    // Each case feeds a unique canary into a field the tool's descriptor marks
    // as a redaction path (note.search `/query`, note.capture `/body`,
    // hook.run `/environment`). The canary must not surface in the disclosure.
    let searchCanary = "CANARY-search-7c1f"
    let captureCanary = "CANARY-capture-9a2d"
    let hookCanary = "CANARY-hook-3e8b-deploy-token"

    let cases: [(input: String, canary: String, expectedTool: String, env: [String: String])] = [
        ("search \(searchCanary)", searchCanary, "note.search", ["CI": "true"]),
        ("note \(captureCanary)", captureCanary, "note.capture", ["CI": "true"]),
        ("hook ondraft-dev", hookCanary, "hook.run", ["DEPLOY_TOKEN": hookCanary]),
    ]

    for testCase in cases {
        let runtime = try makeConfirmingRuntime(hookEnvironment: testCase.env)
        let pending = await runtime.submit(testCase.input, source: .cli)
        guard case let .awaitingConfirmation(_, disclosure, _) = pending else {
            Issue.record("Expected awaitingConfirmation for '\(testCase.input)', got \(pending)"); return
        }
        #expect(disclosure.tool.id == testCase.expectedTool)
        #expect(
            !disclosureText(disclosure).contains(testCase.canary),
            "Disclosure for \(testCase.expectedTool) leaked a descriptor-covered value"
        )
    }
}
