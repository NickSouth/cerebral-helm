import Foundation
import Testing

import CerebralContracts
import CerebralCore
import CerebralTools

/// `window.arrange` (NIC-88): named-frame arrangement of configured apps with
/// honest partial results; a denied Accessibility permission denies the call.

private let APPS = [
    "vscode": "com.microsoft.VSCode",
    "terminal": "com.apple.Terminal",
]

@Test("every entry reports individually; a non-running app is a partial, not a failure")
func arrangeReportsPartialResults() async throws {
    let handler = WindowArrangeHandler(
        capability: MockWindowCapability(arrangeOutcomes: [
            "com.microsoft.VSCode": .arranged
            // Terminal unlisted → not running.
        ]),
        appTargets: APPS
    )

    let output = try await handler.execute(input: Data(
        #"{"arrangement":[{"appId":"vscode","frame":"left-two-thirds"},{"appId":"terminal","frame":"right-third"}]}"#.utf8
    ))
    let decoded = try CerebralHelmWindowArrangeOutput(data: output)
    #expect(decoded.status == .partial)
    #expect(decoded.entries.map(\.status) == [.arranged, .notRunning])
    #expect(decoded.entries[1].message?.contains("never launched") == true)
}

@Test("all entries arranged reports a full success")
func arrangeFullSuccess() async throws {
    let handler = WindowArrangeHandler(
        capability: MockWindowCapability(arrangeOutcomes: [
            "com.microsoft.VSCode": .arranged,
            "com.apple.Terminal": .arranged,
        ]),
        appTargets: APPS
    )
    let output = try await handler.execute(input: Data(
        #"{"arrangement":[{"appId":"vscode","frame":"left-half"},{"appId":"terminal","frame":"right-half"}]}"#.utf8
    ))
    #expect(try CerebralHelmWindowArrangeOutput(data: output).status == .arranged)
}

@Test("an unconfigured app reference and an unsupported app are honest per-entry results")
func arrangeUnknownAndUnsupported() async throws {
    let handler = WindowArrangeHandler(
        capability: MockWindowCapability(arrangeOutcomes: [
            "com.microsoft.VSCode": .unsupported("The application exposes no controllable main window.")
        ]),
        appTargets: APPS
    )
    let output = try await handler.execute(input: Data(
        #"{"arrangement":[{"appId":"ghost-app","frame":"full"},{"appId":"vscode","frame":"full"}]}"#.utf8
    ))
    let decoded = try CerebralHelmWindowArrangeOutput(data: output)
    #expect(decoded.status == .partial)
    #expect(decoded.entries.map(\.status) == [.unknownApp, .unsupported])
}

@Test("a denied Accessibility permission denies the whole call with guidance (FR-SAF-07)")
func arrangePermissionDeniedDeniesCall() async throws {
    let handler = WindowArrangeHandler(
        capability: MockWindowCapability(fault: .permissionDenied),
        appTargets: APPS
    )
    do {
        _ = try await handler.execute(input: Data(#"{"arrangement":[{"appId":"vscode","frame":"full"}]}"#.utf8))
        Issue.record("A denied permission must not produce results.")
    } catch let error as ToolHandlerError {
        guard case let .permissionDenied(message) = error else {
            Issue.record("Expected permissionDenied, got \(error)")
            return
        }
        #expect(message.contains("System Settings"))
    }
}

@Test("the pre-Mac mock composition reports window.arrange unavailable, never a mock success")
func arrangeUnavailablePreMac() async throws {
    let handler = WindowArrangeHandler(
        capability: MockWindowCapability(matrix: .none),
        appTargets: APPS
    )
    do {
        _ = try await handler.execute(input: Data(#"{"arrangement":[{"appId":"vscode","frame":"full"}]}"#.utf8))
        Issue.record("An unavailable capability must not arrange.")
    } catch let error as ToolHandlerError {
        guard case .unavailable = error else {
            Issue.record("Expected unavailable, got \(error)")
            return
        }
    }
}
