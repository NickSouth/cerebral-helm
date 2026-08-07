import Foundation
import CerebralShared

/// System health checks (quick actions phase 5): the `system-status-checks` action.
///
/// **What belongs here is precisely what CI cannot tell you** (owner decision, 2026-08-04). The
/// test suite proves this codebase is self-consistent, and it has to pass for a build to exist at
/// all — so re-running it here would report a fact already guaranteed. What it cannot prove is
/// whether the *world* still matches: a permission revoked in System Settings, an API key that
/// expired, a third-party response whose shape moved, a folder that was renamed. Every check here
/// answers the same question — **could this have changed without me changing code?**
///
/// Two rules follow from that, and they are what keep the surface trustworthy:
///
/// - **Not configured is not failing.** An integration the user never set up is `skipped`, not a
///   red row. A checklist that cries about things nobody asked for stops being read.
/// - **A check never spends anything.** No writes, no quota. A provider with a small daily budget
///   is verified as far as it can be for free — usually "the credential is bound" — and says
///   exactly that rather than implying a live probe it did not make.
public protocol HealthCheck: Sendable {
    var descriptor: HealthCheckDescriptor { get }

    /// Runs the check. Deliberately **non-throwing**: a check that could throw would make the
    /// runner's error handling the thing that decides the verdict, and "this check crashed" is a
    /// result the checklist has to render honestly rather than an exception to swallow.
    func run() async -> HealthCheckOutcome
}

/// What a check is, for rendering and grouping. Static — it does not depend on the run.
public struct HealthCheckDescriptor: Equatable, Sendable {
    public let id: String
    /// The row's text. A short noun phrase, because the checklist reads as a list of things.
    public let title: String
    public let group: HealthCheckGroup
    /// What the check would prove, shown while it is pending so the row is never a bare label.
    public let detail: String?

    public init(id: String, title: String, group: HealthCheckGroup, detail: String? = nil) {
        self.id = id
        self.title = title
        self.group = group
        self.detail = detail
    }
}

/// The sections of the checklist, in render order.
///
/// Grouped rather than one flat list because the groups fail for different reasons and are fixed
/// in different places: a permission is granted in System Settings, a credential in Setup, a
/// provider outage waited out.
public enum HealthCheckGroup: String, CaseIterable, Equatable, Sendable {
    /// macOS grants and surfaces — the ones that change while the app is not looking.
    case permissions
    /// Third-party APIs and the credentials they need.
    case integrations
    /// The local state the app depends on: roots, database, durable files.
    case storage
}

/// What a check found.
public enum HealthCheckOutcome: Equatable, Sendable {
    /// Verified. `detail` says what was actually confirmed, because "passed" alone invites the
    /// reader to assume more was checked than was.
    case passed(detail: String?)
    /// Verified broken. `remediation` is the one step that would fix it, where there is one.
    case failed(reason: String, remediation: String?)
    /// Deliberately not run: not configured, or it would cost quota. Never a failure, and the
    /// reason always says which — a row that reads "skipped" with no explanation is noise.
    case skipped(reason: String)
}

/// A check's state during and after a run. The runner reports the whole set on every change, so a
/// consumer renders a document rather than reconciling a diff.
public struct HealthCheckResult: Equatable, Sendable {
    public enum State: String, Equatable, Sendable {
        case pending
        case running
        case passed
        case failed
        case skipped
    }

    public let descriptor: HealthCheckDescriptor
    public let state: State
    /// The outcome's explanation, or the descriptor's detail while pending.
    public let detail: String?
    public let remediation: String?
    /// How long the check took, once it finished.
    public let durationMs: Int?

    public init(
        descriptor: HealthCheckDescriptor,
        state: State,
        detail: String? = nil,
        remediation: String? = nil,
        durationMs: Int? = nil
    ) {
        self.descriptor = descriptor
        self.state = state
        self.detail = detail
        self.remediation = remediation
        self.durationMs = durationMs
    }

    /// The queued row, before anything has run.
    public static func pending(_ descriptor: HealthCheckDescriptor) -> HealthCheckResult {
        HealthCheckResult(descriptor: descriptor, state: .pending, detail: descriptor.detail)
    }

    /// The finished row for an outcome.
    public static func finished(
        _ descriptor: HealthCheckDescriptor, _ outcome: HealthCheckOutcome, durationMs: Int
    ) -> HealthCheckResult {
        switch outcome {
        case let .passed(detail):
            return HealthCheckResult(
                descriptor: descriptor, state: .passed, detail: detail, durationMs: durationMs
            )
        case let .failed(reason, remediation):
            return HealthCheckResult(
                descriptor: descriptor, state: .failed, detail: reason,
                remediation: remediation, durationMs: durationMs
            )
        case let .skipped(reason):
            return HealthCheckResult(
                descriptor: descriptor, state: .skipped, detail: reason, durationMs: durationMs
            )
        }
    }
}

/// One emission from a run: every check's current state, in registry order.
public struct HealthCheckRun: Equatable, Sendable {
    public let results: [HealthCheckResult]
    /// True once nothing is pending or running — the surface can stop saying "checking".
    public let complete: Bool

    public init(results: [HealthCheckResult], complete: Bool) {
        self.results = results
        self.complete = complete
    }

    /// Failing checks only — the summary line's numerator.
    public var failures: [HealthCheckResult] { results.filter { $0.state == .failed } }
}

/// Runs a set of checks concurrently and reports the whole set as each one lands.
///
/// **Order is the registry's, never completion order.** A checklist whose rows reorder as fast
/// checks overtake slow ones is unreadable, and the reader would lose the row they were watching.
///
/// **Every check is bounded.** A provider that accepts a connection and never answers would
/// otherwise hang the report indefinitely; a check that outlives its deadline is reported as a
/// failure with that reason, which is the honest reading — something the app depends on is not
/// answering.
public struct HealthCheckRunner: Sendable {
    /// How long any one check may take. Generous enough for a cold TLS handshake on a slow link,
    /// short enough that the whole run still settles while the user is looking at it.
    public static let defaultTimeout: TimeInterval = 8

    private let timeout: TimeInterval
    private let clock: any TimeSource

    public init(timeout: TimeInterval = HealthCheckRunner.defaultTimeout, clock: any TimeSource = SystemClock()) {
        self.timeout = timeout
        self.clock = clock
    }

    /// Streams the run. The first emission is every check `pending`, so a surface can render the
    /// full list immediately rather than growing it a row at a time — the reader sees what is
    /// being checked before any of it has an answer.
    public func run(_ checks: [any HealthCheck]) -> AsyncStream<HealthCheckRun> {
        let timeout = self.timeout
        let clock = self.clock
        return AsyncStream { continuation in
            let task = Task {
                var results = checks.map { HealthCheckResult.pending($0.descriptor) }
                continuation.yield(HealthCheckRun(results: results, complete: checks.isEmpty))
                if checks.isEmpty {
                    continuation.finish()
                    return
                }

                await withTaskGroup(of: (Int, HealthCheckResult).self) { group in
                    for (index, check) in checks.enumerated() {
                        group.addTask {
                            let started = clock.now()
                            let outcome = await Self.bounded(check, timeout: timeout)
                            let elapsed = Int(clock.now().timeIntervalSince(started) * 1000)
                            return (index, .finished(check.descriptor, outcome, durationMs: elapsed))
                        }
                    }
                    for await (index, result) in group {
                        results[index] = result
                        let complete = results.allSatisfy {
                            $0.state != .pending && $0.state != .running
                        }
                        continuation.yield(HealthCheckRun(results: results, complete: complete))
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Runs one check with a deadline, racing it against a sleep.
    ///
    /// The loser of the race is cancelled, so a hung request does not outlive the report that
    /// stopped waiting for it.
    static func bounded(_ check: any HealthCheck, timeout: TimeInterval) async -> HealthCheckOutcome {
        await withTaskGroup(of: HealthCheckOutcome?.self) { group in
            group.addTask { await check.run() }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                return Task.isCancelled ? nil : .failed(
                    reason: "Timed out after \(Int(timeout))s.",
                    remediation: "Check your connection, then run the checks again."
                )
            }
            for await outcome in group {
                if let outcome {
                    group.cancelAll()
                    return outcome
                }
            }
            return .failed(reason: "The check did not finish.", remediation: nil)
        }
    }
}
