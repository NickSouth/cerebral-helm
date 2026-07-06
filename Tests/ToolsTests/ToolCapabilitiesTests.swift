import Foundation
import Testing

import CerebralContracts
import CerebralCore
import CerebralTools

/// The capability injection seam (NIC-78): `makeRegistry` binds handlers to the
/// supplied ``ToolCapabilities`` bundle, so a composition can swap the mocks for
/// honest native adapters without touching handlers or the registry.

private func descriptorsDirectory() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // ToolsTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // repository root
        .appendingPathComponent("packages/contracts/fixtures/valid/tools/descriptors", isDirectory: true)
}

/// A stand-in "native" adapter distinguishable from every mock: it reports the
/// app as already running without launching.
private struct FakeAppCapability: AppCapability {
    func open(appID: String) async throws -> AppOpenResult {
        AppOpenResult(appID: appID, launched: false, alreadyRunning: true)
    }
}

@Test("an injected capability implementation reaches its handler through the registry")
func injectedCapabilityReachesHandler() async throws {
    let bundle = ToolCapabilities(
        app: FakeAppCapability(),
        url: MockURLCapability(),
        process: MockProcessCapability(),
        systemStatus: MockSystemStatusCapability(),
        nativeCapabilityIDs: [CapabilityMatrix.Capability.appOpen]
    )
    let registry = try PreMacToolRuntime.makeRegistry(
        descriptorsDirectory: descriptorsDirectory(),
        capabilities: bundle
    )
    let handler = try #require(registry.handler(for: "app.open"))

    let output = try await handler.execute(input: Data(#"{"appId":"vscode"}"#.utf8))
    let decoded = try CerebralHelmAppOpenOutput(data: output)

    // The mock always launches; only the injected fake reports already-running.
    #expect(decoded.alreadyRunning == true)
    #expect(decoded.launched == false)
    #expect(bundle.nativeCapabilityIDs == ["app.open"])
}

@Test("the mock bundle declares no native capability")
func mockBundleDeclaresNoNativeCapability() {
    #expect(ToolCapabilities.mocks().nativeCapabilityIDs.isEmpty)
}
