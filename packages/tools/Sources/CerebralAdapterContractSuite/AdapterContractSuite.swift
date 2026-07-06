import Foundation
import CerebralCore
import CerebralTools

/// The shared adapter contract suite (FR-TOL-04, MAC-ADAPTER-6): one set of
/// executable contract cases that every capability bundle — the pre-Mac mocks and
/// the honest macOS adapters — must satisfy.
///
/// The suite is deliberately test-framework-neutral: a case *throws*
/// ``AdapterContractViolation`` instead of asserting, so the same cases run under
/// swift-testing (`Tests/ToolsTests`) and under the Xcode XCTest target that
/// exercises the native adapters (MAC-ADAPTER-6). Runners supply the bundle, the
/// fixtures the environment can honestly satisfy, and iterate the cases.
public struct AdapterContractViolation: Error, CustomStringConvertible {
    public let caseName: String
    public let reason: String

    public init(caseName: String, reason: String) {
        self.caseName = caseName
        self.reason = reason
    }

    public var description: String { "[\(caseName)] \(reason)" }
}

/// One named, self-contained contract check.
public struct AdapterContractCase: Sendable {
    public let name: String
    public let run: @Sendable () async throws -> Void

    public init(name: String, run: @escaping @Sendable () async throws -> Void) {
        self.name = name
        self.run = run
    }
}

/// The environment-specific inputs a runner promises the bundle can satisfy: the
/// mock runner uses the deterministic mock fixtures; the native runner supplies
/// references that genuinely exist on the target Mac. The *checks* are identical —
/// only the inputs differ (MAC-ADAPTER-6: platform detail stays in inputs and
/// diagnostics, never in the contract).
public struct AdapterContractFixtures: Sendable {
    /// A configured app reference id expected to open.
    public var appID: String
    /// A configured URL reference id expected to open.
    public var urlID: String
    /// The URL `urlID` must resolve to; `nil` skips the equality check.
    public var expectedResolvedURL: String?
    /// A hook id present in the runner's ``HookCatalog``.
    public var hookID: String
    /// The exact invocation behind `hookID`, expected to succeed with exit code 0.
    public var hookInvocation: HookInvocation
    /// Expected stdout of the succeeding invocation; `nil` skips the check.
    public var expectedHookStdout: String?
    /// A note-search query the runner's knowledge service answers with ≥ 1 hit.
    public var searchQuery: String
    /// Metrics the status capability is asked for (shape-checked per reading).
    public var metrics: [SystemMetricID]

    public init(
        appID: String,
        urlID: String,
        expectedResolvedURL: String? = nil,
        hookID: String,
        hookInvocation: HookInvocation,
        expectedHookStdout: String? = nil,
        searchQuery: String,
        metrics: [SystemMetricID] = [.cpu, .memory]
    ) {
        self.appID = appID
        self.urlID = urlID
        self.expectedResolvedURL = expectedResolvedURL
        self.hookID = hookID
        self.hookInvocation = hookInvocation
        self.expectedHookStdout = expectedHookStdout
        self.searchQuery = searchQuery
        self.metrics = metrics
    }
}

/// A runner-provided way to provoke one canonical failure, with the error kind
/// the contract requires (PRD §13.2). Mocks provoke via fault injection; native
/// adapters via genuinely failing inputs (a missing app, a denied permission).
public struct FailureExpectation: Sendable {
    public let name: String
    public let expected: NativeCapabilityError
    public let provoke: @Sendable () async throws -> Void

    public init(name: String, expected: NativeCapabilityError, provoke: @escaping @Sendable () async throws -> Void) {
        self.name = name
        self.expected = expected
        self.provoke = provoke
    }
}

enum ContractCheck {
    static func expect(_ condition: Bool, _ caseName: String, _ reason: @autoclosure () -> String) throws {
        guard condition else { throw AdapterContractViolation(caseName: caseName, reason: reason()) }
    }

    /// Case-kind equality for ``NativeCapabilityError``: associated payloads are
    /// diagnostics and legitimately differ per adapter (a mock says "safari", a
    /// native adapter names the real bundle id), so the contract compares only
    /// the failure kind.
    static func sameKind(_ lhs: NativeCapabilityError, _ rhs: NativeCapabilityError) -> Bool {
        kind(lhs) == kind(rhs)
    }

    static func kind(_ error: NativeCapabilityError) -> String {
        switch error {
        case .unavailable: return "unavailable"
        case .permissionDenied: return "permissionDenied"
        case .notFound: return "notFound"
        case .timedOut: return "timedOut"
        case .cancelled: return "cancelled"
        case .adapterFailure: return "adapterFailure"
        }
    }
}
