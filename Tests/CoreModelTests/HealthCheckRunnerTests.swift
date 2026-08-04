import Foundation
import Testing

import CerebralCore
import CerebralShared
import CerebralTools

/// Quick actions phase 5: the health-check runner.
///
/// Its guarantees are all about **honesty under concurrency** — the order rows appear in, the fact
/// that a hung check cannot hold the report open, and that "complete" means complete.

private func descriptor(_ id: String, _ group: HealthCheckGroup = .integrations) -> HealthCheckDescriptor {
    HealthCheckDescriptor(id: id, title: id, group: group, detail: "what it proves")
}

/// A check that takes a controllable amount of time, so completion order can be forced to differ
/// from registry order.
private struct SlowCheck: HealthCheck {
    let descriptor: HealthCheckDescriptor
    let delay: Duration
    let outcome: HealthCheckOutcome

    func run() async -> HealthCheckOutcome {
        try? await Task.sleep(for: delay)
        return outcome
    }
}

/// A check that never returns — the provider that accepts a connection and says nothing.
private struct HangingCheck: HealthCheck {
    let descriptor: HealthCheckDescriptor

    func run() async -> HealthCheckOutcome {
        try? await Task.sleep(for: .seconds(3600))
        return .passed(detail: "unreachable")
    }
}

@Test("the first emission lists every check as pending, before any of them has an answer")
func runnerAnnouncesTheWorkFirst() async throws {
    let checks: [any HealthCheck] = [
        StaticHealthCheck(descriptor: descriptor("a"), outcome: .passed(detail: "ok")),
        StaticHealthCheck(descriptor: descriptor("b"), outcome: .skipped(reason: "not set up"))
    ]

    var emissions: [HealthCheckRun] = []
    for await run in HealthCheckRunner().run(checks) {
        emissions.append(run)
    }

    let first = try #require(emissions.first)
    // The reader sees WHAT is being checked immediately, rather than watching a list grow a row at
    // a time with no sense of how much is left.
    #expect(first.results.map(\.state) == [.pending, .pending])
    #expect(first.results.map(\.descriptor.id) == ["a", "b"])
    #expect(!first.complete)
    // And every row carries its descriptor's detail while pending, so none is a bare label.
    #expect(first.results.allSatisfy { $0.detail == "what it proves" })
}

@Test("rows keep registry order even when a later check finishes first")
func runnerKeepsRegistryOrder() async throws {
    let checks: [any HealthCheck] = [
        SlowCheck(descriptor: descriptor("slow"), delay: .milliseconds(120), outcome: .passed(detail: "ok")),
        SlowCheck(descriptor: descriptor("fast"), delay: .milliseconds(1), outcome: .failed(reason: "no", remediation: nil))
    ]

    var emissions: [HealthCheckRun] = []
    for await run in HealthCheckRunner().run(checks) {
        emissions.append(run)
    }

    // A checklist whose rows reorder as fast checks overtake slow ones is unreadable — the reader
    // loses the row they were watching mid-run.
    for run in emissions {
        #expect(run.results.map(\.descriptor.id) == ["slow", "fast"])
    }
    let final = try #require(emissions.last)
    #expect(final.complete)
    #expect(final.results.map(\.state) == [.passed, .failed])
}

@Test("complete is true only once nothing is outstanding")
func runnerReportsCompletionHonestly() async throws {
    let checks: [any HealthCheck] = (0..<3).map {
        SlowCheck(
            descriptor: descriptor("c\($0)"),
            delay: .milliseconds($0 * 20 + 1),
            outcome: .passed(detail: "ok")
        )
    }

    var emissions: [HealthCheckRun] = []
    for await run in HealthCheckRunner().run(checks) {
        emissions.append(run)
    }

    // Exactly one emission may claim completion, and it must be the last.
    #expect(emissions.filter(\.complete).count == 1)
    #expect(emissions.last?.complete == true)
    // Every intermediate emission still had something pending, so none of them claimed it.
    for run in emissions.dropLast() {
        #expect(run.results.contains { $0.state == .pending })
    }
}

@Test("a hung check fails on its deadline rather than holding the whole run open")
func runnerBoundsEveryCheck() async throws {
    let checks: [any HealthCheck] = [
        HangingCheck(descriptor: descriptor("hangs")),
        StaticHealthCheck(descriptor: descriptor("fine"), outcome: .passed(detail: "ok"))
    ]

    var final: HealthCheckRun?
    for await run in HealthCheckRunner(timeout: 0.2).run(checks) {
        final = run
    }

    let result = try #require(final)
    #expect(result.complete)
    // Reported as a failure with the reason, which is the honest reading: something the app
    // depends on is not answering.
    #expect(result.results[0].state == .failed)
    #expect(result.results[0].detail?.contains("Timed out") == true)
    // And the healthy check still reported, rather than being held hostage by its neighbour.
    #expect(result.results[1].state == .passed)
}

@Test("an empty inventory completes immediately instead of hanging on nothing")
func runnerHandlesAnEmptyInventory() async throws {
    var emissions: [HealthCheckRun] = []
    for await run in HealthCheckRunner().run([]) {
        emissions.append(run)
    }

    #expect(emissions.count == 1)
    #expect(emissions.first?.complete == true)
    #expect(emissions.first?.results.isEmpty == true)
}

@Test("outcomes map onto states without inventing a verdict")
func outcomesMapOntoStates() {
    let base = descriptor("x")

    let passed = HealthCheckResult.finished(base, .passed(detail: "Answered."), durationMs: 12)
    #expect(passed.state == .passed)
    #expect(passed.detail == "Answered.")
    #expect(passed.durationMs == 12)

    let failed = HealthCheckResult.finished(
        base, .failed(reason: "Rejected.", remediation: "Re-enter the key."), durationMs: 8
    )
    #expect(failed.state == .failed)
    #expect(failed.remediation == "Re-enter the key.")

    // Skipped is its own state, never folded into passed or failed: an integration nobody set up
    // is not working, and it is also not broken.
    let skipped = HealthCheckResult.finished(base, .skipped(reason: "Not set up."), durationMs: 1)
    #expect(skipped.state == .skipped)
    #expect(skipped.detail == "Not set up.")
    #expect(skipped.remediation == nil)
}

@Test("failures are counted, and a skip is not one of them")
func failuresExcludeSkips() {
    let run = HealthCheckRun(
        results: [
            .finished(descriptor("a"), .passed(detail: nil), durationMs: 1),
            .finished(descriptor("b"), .skipped(reason: "not set up"), durationMs: 1),
            .finished(descriptor("c"), .failed(reason: "broke", remediation: nil), durationMs: 1)
        ],
        complete: true
    )

    #expect(run.failures.map(\.descriptor.id) == ["c"])
}
