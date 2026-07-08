import Foundation
import CerebralContracts
import CerebralCore
import CerebralTools

/// Handler-level contract cases (AC-33.1, AC-33.3): each tool's bound handler is
/// invoked directly with a happy-path input and its output decoded against the
/// generated contract type. Handlers own I/O validation, so these cases are
/// phase-independent — the executor's availability gate is covered elsewhere.
///
/// The runner supplies a registry already composed with the bundle under test
/// (mock or native), a knowledge service, and a hook catalog containing
/// `fixtures.hookID`.
public extension AdapterContractSuite {
    static func handlerCases(
        registry: ToolRegistry,
        fixtures: AdapterContractFixtures
    ) -> [AdapterContractCase] {
        @Sendable func handler(_ toolID: String, _ caseName: String) throws -> any ToolHandler {
            guard let handler = registry.handler(for: toolID) else {
                throw AdapterContractViolation(caseName: caseName, reason: "no handler bound for '\(toolID)'")
            }
            return handler
        }

        return [
            AdapterContractCase(name: "app.open handler contract") {
                let output = try await handler("app.open", "app.open handler contract")
                    .execute(input: Data(#"{"appId":"\#(fixtures.appID)"}"#.utf8))
                let decoded = try CerebralHelmAppOpenOutput(data: output)
                try ContractCheck.expect(decoded.appID == fixtures.appID, "app.open handler contract", "output must echo the app id")
                try ContractCheck.expect(decoded.launched || decoded.alreadyRunning, "app.open handler contract", "an opened app is launched or already running")
            },
            AdapterContractCase(name: "url.open handler contract") {
                let output = try await handler("url.open", "url.open handler contract")
                    .execute(input: Data(#"{"urlId":"\#(fixtures.urlID)"}"#.utf8))
                let decoded = try CerebralHelmURLOpenOutput(data: output)
                try ContractCheck.expect(decoded.urlID == fixtures.urlID, "url.open handler contract", "output must echo the url id")
                try ContractCheck.expect(decoded.opened, "url.open handler contract", "the configured URL must report opened")
            },
            AdapterContractCase(name: "system.status.read handler contract") {
                let requested = fixtures.metrics.map { #""\#($0.rawValue)""# }.joined(separator: ",")
                let output = try await handler("system.status.read", "system.status.read handler contract")
                    .execute(input: Data(#"{"metrics":[\#(requested)]}"#.utf8))
                let decoded = try CerebralHelmSystemStatusReadOutput(data: output)
                try ContractCheck.expect(
                    decoded.metrics.count == fixtures.metrics.count,
                    "system.status.read handler contract",
                    "one output entry per requested metric (got \(decoded.metrics.count), requested \(fixtures.metrics.count))"
                )
            },
            AdapterContractCase(name: "note.capture handler contract") {
                let output = try await handler("note.capture", "note.capture handler contract")
                    .execute(input: Data(#"{"title":"t","body":"b","kind":"idea"}"#.utf8))
                let decoded = try CerebralHelmNoteCaptureOutput(data: output)
                try ContractCheck.expect(decoded.created, "note.capture handler contract", "capture must report created")
                try ContractCheck.expect(!decoded.noteID.isEmpty, "note.capture handler contract", "capture must return a note id")
            },
            AdapterContractCase(name: "note.search handler contract") {
                let output = try await handler("note.search", "note.search handler contract")
                    .execute(input: Data(#"{"query":"\#(fixtures.searchQuery)"}"#.utf8))
                let decoded = try CerebralHelmNoteSearchOutput(data: output)
                try ContractCheck.expect(!decoded.results.isEmpty, "note.search handler contract", "the fixture query must return at least one result")
            },
            AdapterContractCase(name: "hook.run handler contract") {
                let output = try await handler("hook.run", "hook.run handler contract")
                    .execute(input: Data(#"{"hookId":"\#(fixtures.hookID)"}"#.utf8))
                let decoded = try CerebralHelmHookRunOutput(data: output)
                try ContractCheck.expect(decoded.hookID == fixtures.hookID, "hook.run handler contract", "output must echo the hook id")
                try ContractCheck.expect(decoded.exitCode == 0, "hook.run handler contract", "the fixture hook must exit 0 (got \(decoded.exitCode))")
                if let expected = fixtures.expectedHookStdout {
                    try ContractCheck.expect(decoded.stdout == expected, "hook.run handler contract", "stdout was '\(decoded.stdout)', expected '\(expected)'")
                }
            },
            AdapterContractCase(name: "hook.run refuses an unregistered hook id (AC-33.2)") {
                do {
                    _ = try await handler("hook.run", "hook.run refuses an unregistered hook id (AC-33.2)")
                        .execute(input: Data(#"{"hookId":"contract-suite-unregistered"}"#.utf8))
                } catch ToolHandlerError.invalidInput {
                    return
                }
                throw AdapterContractViolation(
                    caseName: "hook.run refuses an unregistered hook id (AC-33.2)",
                    reason: "an unregistered hook id must be rejected as invalid input before any process is touched"
                )
            },
            AdapterContractCase(name: "app.open rejects malformed input (AC-33.1)") {
                do {
                    _ = try await handler("app.open", "app.open rejects malformed input (AC-33.1)")
                        .execute(input: Data(#"{"appId":123}"#.utf8))
                } catch ToolHandlerError.invalidInput {
                    return
                }
                throw AdapterContractViolation(
                    caseName: "app.open rejects malformed input (AC-33.1)",
                    reason: "a non-string appId must be rejected as invalid input before the adapter runs"
                )
            },
        ]
    }
}
