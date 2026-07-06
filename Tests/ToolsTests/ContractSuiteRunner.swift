import Foundation
import Testing

import CerebralAdapterContractSuite
import CerebralCore
import CerebralTools

/// Shared swift-testing runner for the framework-neutral adapter contract suite:
/// a case that throws ``AdapterContractViolation`` becomes a recorded issue with
/// the case name in the message. The Xcode test target has its own XCTest-flavored
/// runner over the same cases (MAC-ADAPTER-6).
func runContractCases(_ cases: [AdapterContractCase]) async {
    for contractCase in cases {
        do {
            try await contractCase.run()
        } catch let violation as AdapterContractViolation {
            Issue.record("\(violation)")
        } catch {
            Issue.record("[\(contractCase.name)] unexpected error: \(error)")
        }
    }
}

/// The mock composition every ToolsTests runner shares: the deterministic mock
/// bundle plus the fixture inputs it satisfies. Mirrors the values the pre-suite
/// per-file tests asserted, so extracting the suite loses no coverage.
enum MockContractComposition {
    static let hookInvocation = HookInvocation(
        executable: "/usr/bin/just",
        arguments: ["build"],
        workingDirectory: "/repo",
        environment: ["CI": "true"]
    )

    static let fixtures = AdapterContractFixtures(
        appID: "vscode",
        urlID: "github",
        expectedResolvedURL: "https://example.com/github",
        hookID: "ondraft-dev",
        hookInvocation: hookInvocation,
        expectedHookStdout: "built",
        searchQuery: "fixture",
        metrics: [.cpu, .memory]
    )

    static func bundle(matrix: CapabilityMatrix = .allAvailable) -> ToolCapabilities {
        ToolCapabilities(
            app: MockAppCapability(matrix: matrix),
            url: MockURLCapability(matrix: matrix),
            process: MockProcessCapability(matrix: matrix, stdout: "built", durationMs: 12),
            systemStatus: MockSystemStatusCapability(matrix: matrix)
        )
    }
}
