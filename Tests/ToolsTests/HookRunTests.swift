import Foundation
import Testing

import CerebralAdapterContractSuite
import CerebralCore
import CerebralTools

/// NIC-33-B (PRE-SAFETY-6): hook.run executes only configured, allowlisted hooks.
///
/// AC-33.2 arbitrary shell input is impossible. The checks live in the shared
/// contract suite (the exact-invocation execution, stdout/exit-code echo, and the
/// unregistered-id rejection); this file runs the hook-related cases against the
/// mock process capability. The native process adapter satisfies the same cases
/// (MAC-ADAPTER-2/6).

@Test("hook.run executes a registered hook and refuses an arbitrary id (AC-33.2)")
func hookRunRefusesArbitraryHooks() async throws {
    var builder = ToolRegistryBuilder()
    let descriptors = try ToolDescriptorCatalog.loadDescriptors(
        directory: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // ToolsTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repository root
            .appendingPathComponent("packages/contracts/fixtures/valid/tools/descriptors", isDirectory: true)
    )
    let hookDescriptor = try #require(descriptors.first { $0.id == "hook.run" })
    try builder.register(
        descriptor: hookDescriptor,
        handler: HookRunHandler(
            catalog: HookCatalog([MockContractComposition.fixtures.hookID: MockContractComposition.hookInvocation]),
            capability: MockProcessCapability(stdout: "built", durationMs: 12)
        )
    )
    let registry = builder.build()

    let hookCases = AdapterContractSuite.handlerCases(
        registry: registry,
        fixtures: MockContractComposition.fixtures
    ).filter { $0.name.hasPrefix("hook.run") }

    #expect(hookCases.count == 2)
    await runContractCases(hookCases)
}
