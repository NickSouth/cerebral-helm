// Shared polling deadline for the publisher tests (CI flakiness fix, 2026-08-05).
#if canImport(AppKit)
import Foundation

/// How long a test will wait for asynchronous work before giving up.
///
/// Every publisher test polls for an effect produced by a fire-and-forget `Task` — an emitted event,
/// a warmed cache, a bound socket. None of those expose a completion handle to await, so polling is
/// the only option, and the deadline is purely *how patient we are with the scheduler*.
///
/// It used to be 1–3 seconds, chosen against a fast local machine. On a shared, 2-core CI runner
/// with the suite running in parallel, that is not enough time for the cooperative pool to get
/// around to the work: PR #15 went red twice on two unrelated tests, and both passed on a rerun of
/// the identical commit. Tuning individual call sites just moved the failure somewhere else.
///
/// So the number is gone from the call sites. It was never a specification — no test meant "fail if
/// this takes 3.1 seconds" — it was a safety margin, and a safety margin belongs in one place, set
/// generously. **This weakens no assertion**: a condition that never becomes true still fails the
/// test. It costs nothing on a green run either, because every waiter returns the moment its
/// condition holds; the deadline is only reached by a test that was going to fail anyway.
let testWaitDeadline: TimeInterval = 30

/// Poll `condition` until it holds or ``testWaitDeadline`` passes.
///
/// Wall-clock based rather than iteration-counting: a loaded runner can stretch each `Task.sleep`
/// well past its nominal 20 ms, and counting iterations silently shortens the real budget exactly
/// when the machine is slowest — which is when the patience is needed.
func waitUntil(_ condition: () -> Bool) async {
    let deadline = Date().addingTimeInterval(testWaitDeadline)
    while Date() < deadline {
        if condition() { return }
        try? await Task.sleep(nanoseconds: 20_000_000)
    }
}
#endif
