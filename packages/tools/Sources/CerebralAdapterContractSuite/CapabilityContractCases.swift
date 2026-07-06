import Foundation
import CerebralCore
import CerebralTools

/// Capability-level contract cases: they call the bundle's capability protocols
/// directly and check result shapes, so they hold for any conforming adapter.
public enum AdapterContractSuite {
    public static func capabilityCases(
        bundle: ToolCapabilities,
        fixtures: AdapterContractFixtures
    ) -> [AdapterContractCase] {
        [
            AdapterContractCase(name: "app.open result shape") {
                let result = try await bundle.app.open(appID: fixtures.appID)
                try ContractCheck.expect(result.appID == fixtures.appID, "app.open result shape", "result must echo the requested app id (got '\(result.appID)')")
                try ContractCheck.expect(result.launched || result.alreadyRunning, "app.open result shape", "an opened app is launched or already running")
            },
            AdapterContractCase(name: "url.open result shape") {
                let result = try await bundle.url.open(urlID: fixtures.urlID)
                try ContractCheck.expect(result.urlID == fixtures.urlID, "url.open result shape", "result must echo the requested url id (got '\(result.urlID)')")
                try ContractCheck.expect(result.opened, "url.open result shape", "the configured URL must report opened")
                try ContractCheck.expect(!result.resolvedURL.isEmpty, "url.open result shape", "the resolved URL must not be empty")
                if let expected = fixtures.expectedResolvedURL {
                    try ContractCheck.expect(result.resolvedURL == expected, "url.open result shape", "resolved '\(result.resolvedURL)', expected '\(expected)'")
                }
            },
            AdapterContractCase(name: "process run result shape") {
                let result = try await bundle.process.run(fixtures.hookInvocation)
                try ContractCheck.expect(result.exitCode == 0, "process run result shape", "the succeeding invocation must exit 0 (got \(result.exitCode))")
                try ContractCheck.expect(!result.timedOut, "process run result shape", "a completed invocation must not report timedOut")
                try ContractCheck.expect(result.durationMs >= 0, "process run result shape", "durationMs must be non-negative")
                // The adapter must run with exactly the configured environment —
                // nothing inherited, nothing dropped (FR-TOL-05 bounded environment).
                try ContractCheck.expect(
                    result.environment == fixtures.hookInvocation.environment,
                    "process run result shape",
                    "the reported environment must equal the configured invocation environment"
                )
                if let expected = fixtures.expectedHookStdout {
                    try ContractCheck.expect(result.stdout == expected, "process run result shape", "stdout was '\(result.stdout)', expected '\(expected)'")
                }
            },
            AdapterContractCase(name: "system status reading shape") {
                let readings = try await bundle.systemStatus.readMetrics(fixtures.metrics)
                try ContractCheck.expect(
                    readings.map(\.id) == fixtures.metrics,
                    "system status reading shape",
                    "exactly one reading per requested metric, in request order (got \(readings.map(\.id)))"
                )
                for reading in readings where reading.availability != .available {
                    // An unavailable/stale/loading/disconnected metric carries no
                    // value — the UI must never render a number it cannot trust.
                    try ContractCheck.expect(
                        reading.value == nil,
                        "system status reading shape",
                        "metric '\(reading.id)' is \(reading.availability.rawValue) but carries a value"
                    )
                }
            },
        ]
    }

    /// Failure-expectation cases (PRD §13.2): each runner-provided scenario must
    /// throw the expected ``NativeCapabilityError`` kind — succeeding, or failing
    /// with a different kind, violates the contract.
    public static func failureCases(_ expectations: [FailureExpectation]) -> [AdapterContractCase] {
        expectations.map { expectation in
            AdapterContractCase(name: expectation.name) {
                do {
                    try await expectation.provoke()
                } catch let error as NativeCapabilityError {
                    try ContractCheck.expect(
                        ContractCheck.sameKind(error, expectation.expected),
                        expectation.name,
                        "expected \(ContractCheck.kind(expectation.expected)), got \(ContractCheck.kind(error))"
                    )
                    return
                }
                throw AdapterContractViolation(
                    caseName: expectation.name,
                    reason: "expected \(ContractCheck.kind(expectation.expected)), but the operation succeeded"
                )
            }
        }
    }
}
