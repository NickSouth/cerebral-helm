import Foundation
import Testing

import CerebralContracts
import CerebralCore
import CerebralTools

/// NIC-33-B (PRE-SAFETY-6): hook.run executes only configured, allowlisted hooks.
///
/// AC-33.2 arbitrary shell input is impossible.

@Test("hook.run executes a registered hook and refuses an arbitrary id (AC-33.2)")
func hookRunRefusesArbitraryHooks() async throws {
    let invocation = HookInvocation(
        executable: "/usr/bin/just",
        arguments: ["build"],
        workingDirectory: "/repo",
        environment: ["CI": "true"]
    )
    let handler = HookRunHandler(
        catalog: HookCatalog(["ondraft-dev": invocation]),
        capability: MockProcessCapability(stdout: "built", durationMs: 12)
    )

    // A registered hook id runs the exact configured invocation.
    let output = try await handler.execute(input: Data(#"{"hookId":"ondraft-dev"}"#.utf8))
    let decoded = try CerebralHelmHookRunOutput(data: output)
    #expect(decoded.exitCode == 0)
    #expect(decoded.stdout == "built")
    #expect(decoded.hookID == "ondraft-dev")
    #expect(decoded.environment == ["CI": "true"])

    // An unregistered id is rejected before any process is touched.
    do {
        _ = try await handler.execute(input: Data(#"{"hookId":"rm-rf-slash"}"#.utf8))
        Issue.record("An unregistered hook id must not execute.")
    } catch let error as ToolHandlerError {
        guard case .invalidInput = error else {
            Issue.record("Expected invalidInput, got \(error)")
            return
        }
    }
}
