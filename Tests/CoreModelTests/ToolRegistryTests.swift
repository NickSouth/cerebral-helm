import Foundation
import Testing

import CerebralContracts
import CerebralCore

/// NIC-28 (PRE-SAFETY-1): validated tool registry.
///
/// AC-28.1 invalid descriptors block registration; AC-28.2 the listing is stable
/// for CLI and settings; AC-28.3 handlers cannot be invoked without validation.
/// Also covers the stricter-only `config/tools` overlay (PRD §10.3).

private func repoRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // CoreModelTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // repository root
}

private func validDescriptorsDirectory() -> URL {
    repoRoot().appendingPathComponent("packages/contracts/fixtures/valid/tools/descriptors", isDirectory: true)
}

private func invalidDescriptorsDirectory() -> URL {
    repoRoot().appendingPathComponent("packages/contracts/fixtures/invalid/tools/descriptors", isDirectory: true)
}

private let mvpToolIDs: Set<String> = [
    "app.open", "url.open", "hook.run", "note.capture",
    "note.search", "mode.apply", "system.status.read", "window.arrange",
    "apps.list", "network.speed.test",
]

private struct StubHandler: ToolHandler {
    let toolID: String
    func execute(input: Data) async throws -> Data { input }
}

private func loadValidDescriptors() throws -> [CerebralHelmToolDescriptor] {
    try ToolDescriptorCatalog.loadDescriptors(directory: validDescriptorsDirectory())
}

private func registry(from descriptors: [CerebralHelmToolDescriptor]) throws -> ToolRegistry {
    var builder = ToolRegistryBuilder()
    for descriptor in descriptors {
        try builder.register(descriptor: descriptor, handler: StubHandler(toolID: descriptor.id))
    }
    return builder.build()
}

@Test("the canonical descriptor set decodes to every MVP tool")
func loadsEveryDescriptor() throws {
    let descriptors = try loadValidDescriptors()
    #expect(Set(descriptors.map(\.id)) == mvpToolIDs)
}

@Test("a descriptor missing required policy metadata fails to load (AC-28.1)")
func invalidDescriptorBlocksRegistration() {
    // The invalid fixtures omit `risk` / `confirmationPolicyKey`; strict decode
    // rejects them before they can reach the registry.
    #expect(throws: (any Error).self) {
        _ = try ToolDescriptorCatalog.loadDescriptors(directory: invalidDescriptorsDirectory())
    }
}

@Test("the registry lists every validated tool in a stable, sorted order (AC-28.2)")
func listingIsStable() throws {
    let descriptors = try loadValidDescriptors()

    let listing = try registry(from: descriptors).registeredTools.map(\.id)
    #expect(listing == listing.sorted())
    #expect(Set(listing) == mvpToolIDs)

    // Registration order does not change the listing.
    let reversed = try registry(from: descriptors.reversed()).registeredTools.map(\.id)
    #expect(reversed == listing)
}

@Test("registering a duplicate tool id is rejected")
func duplicateIDIsRejected() throws {
    let tool = try loadValidDescriptors()[0]
    var builder = ToolRegistryBuilder()
    try builder.register(descriptor: tool, handler: StubHandler(toolID: tool.id))

    #expect(throws: ToolRegistrationError.duplicateID(tool.id)) {
        try builder.register(descriptor: tool, handler: StubHandler(toolID: tool.id))
    }
}

@Test("a handler must match its descriptor, and only validated handlers resolve (AC-28.3)")
func handlerBindingRequiresValidation() throws {
    let tool = try #require(loadValidDescriptors().first { $0.id == "system.status.read" })

    var rejecting = ToolRegistryBuilder()
    #expect(throws: ToolRegistrationError.handlerIDMismatch(descriptorID: tool.id, handlerID: "wrong.id")) {
        try rejecting.register(descriptor: tool, handler: StubHandler(toolID: "wrong.id"))
    }
    // A rejected registration never makes the handler reachable.
    #expect(rejecting.build().handler(for: tool.id) == nil)

    var accepting = ToolRegistryBuilder()
    try accepting.register(descriptor: tool, handler: StubHandler(toolID: tool.id))
    #expect(accepting.build().handler(for: tool.id) != nil)
}

@Test("a config overlay may tighten but never weaken a descriptor")
func overlayIsStricterOnly() throws {
    // app.open: local_write, 30000ms, pre-Mac unavailable.
    let appOpen = try #require(loadValidDescriptors().first { $0.id == "app.open" })

    func registerOverlay(_ overlay: ConfiguredTool) throws -> RegisteredTool {
        var builder = ToolRegistryBuilder()
        try builder.register(descriptor: appOpen, handler: StubHandler(toolID: appOpen.id), overlay: overlay)
        return try #require(builder.build().tool(appOpen.id))
    }

    // Tightening: a shorter timeout is accepted and wins.
    let tightened = try registerOverlay(ConfiguredTool(id: "app.open", risk: "local_write", timeoutMs: 5000, availableInPreMac: false))
    #expect(tightened.effectiveTimeoutMs == 5000)
    #expect(tightened.availableInPreMac == false)

    // Extending the timeout is rejected.
    #expect(throws: (any Error).self) {
        _ = try registerOverlay(ConfiguredTool(id: "app.open", risk: "local_write", timeoutMs: 60000, availableInPreMac: false))
    }
    // Changing the risk is rejected — the descriptor risk is authoritative.
    #expect(throws: (any Error).self) {
        _ = try registerOverlay(ConfiguredTool(id: "app.open", risk: "read_only", timeoutMs: 30000, availableInPreMac: false))
    }
    // Enabling a pre-Mac availability the descriptor disables is rejected.
    #expect(throws: (any Error).self) {
        _ = try registerOverlay(ConfiguredTool(id: "app.open", risk: "local_write", timeoutMs: 30000, availableInPreMac: true))
    }
}

@Test("the shipped config overlays validate cleanly against their descriptors")
func shippedOverlaysAreConsistent() throws {
    let descriptors = try loadValidDescriptors()
    let overlays = try ConfiguredToolRegistry.load(configDirectory: repoRoot().appendingPathComponent("config", isDirectory: true))

    var builder = ToolRegistryBuilder()
    for descriptor in descriptors {
        try builder.register(
            descriptor: descriptor,
            handler: StubHandler(toolID: descriptor.id),
            overlay: overlays.tool(id: descriptor.id)
        )
    }
    let registry = builder.build()

    #expect(registry.tool("system.status.read")?.availableInPreMac == true)
    #expect(registry.tool("hook.run")?.availableInPreMac == false)
    // Every shipped tool is available on macOS; the phase-matching accessor
    // reads the right flag for each phase.
    #expect(registry.tool("hook.run")?.availableOnMacOS == true)
    #expect(registry.tool("hook.run")?.isAvailable(in: .preMac) == false)
    #expect(registry.tool("hook.run")?.isAvailable(in: .macOS) == true)
    #expect(registry.tool("network.speed.test")?.availableInPreMac == false)
    #expect(registry.tool("network.speed.test")?.availableOnMacOS == true)
    #expect(registry.toolIDs.count == 10)
}
