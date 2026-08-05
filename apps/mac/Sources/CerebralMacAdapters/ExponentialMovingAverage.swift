// Time-constant smoothing for the streamed load metrics (NIC-158).
#if canImport(AppKit)
import Foundation

/// A time-constant exponential moving average over an irregular sample stream.
///
/// Why the System Health bars need one (NIC-158): CPU percentage is the fraction of *total machine
/// capacity* busy during one 2-second window. What actually matters to the user — heat, fan, battery,
/// responsiveness — is the area under that curve over time, not the peak. A 2-second burst at 100%
/// costs nothing; two minutes at 80% spins the fan. Averaging measures exactly that, which means one
/// mechanism delivers both things the bar needs: the displayed value moves gradually instead of
/// jumping, and a "load is high" colour can only be reached by *sustained* load, never by a transient
/// spike. Frequent spiking does accumulate — correctly, since thermally "100% half the time" and
/// "a steady 50%" are the same thing.
///
/// Weighting is by **elapsed time, not sample count**, so an irregular cadence (a tick that runs
/// late, or the immediate tick after the publisher resumes) weights correctly rather than counting
/// as one uniform step. `timeConstant` is the time to close ~63% of a step change.
///
/// Two rules keep it honest, both enforced by the caller reading `reset()`:
/// - It **seeds from the first real sample** rather than ramping up from zero, so a fresh launch
///   never renders a fabricated low reading climbing into place.
/// - It **never coasts**. A tick with no trustworthy sample resets the history, so a recovered
///   channel re-seeds from a real reading instead of resuming a stale curve.
struct ExponentialMovingAverage {
    /// Time to close ~63% of a step change. Larger = calmer and laggier.
    let timeConstant: TimeInterval

    private var value: Double?
    private var lastSampledAt: Date?

    init(timeConstant: TimeInterval) {
        self.timeConstant = timeConstant
    }

    /// The current smoothed value, or nil before the first sample.
    var current: Double? { value }

    /// Fold in one sample taken at `sampledAt`, returning the new smoothed value.
    ///
    /// The first sample after construction or `reset()` is adopted verbatim — there is no history
    /// to blend it with, and inventing one would mean rendering a value the machine never reported.
    @discardableResult
    mutating func update(_ sample: Double, at sampledAt: Date) -> Double {
        defer { lastSampledAt = sampledAt }
        guard let previous = value, let last = lastSampledAt else {
            value = sample
            return sample
        }
        let elapsed = sampledAt.timeIntervalSince(last)
        // Non-monotonic or duplicate timestamps contribute nothing rather than producing a
        // negative alpha (which would amplify the difference instead of damping it).
        guard elapsed > 0, timeConstant > 0 else {
            return previous
        }
        // A long gap drives alpha toward 1, so the average snaps to the fresh sample instead of
        // crawling out of history that is no longer describing the machine.
        let alpha = 1 - exp(-elapsed / timeConstant)
        let next = previous + alpha * (sample - previous)
        value = next
        return next
    }

    /// Drop the history so the next sample re-seeds.
    mutating func reset() {
        value = nil
        lastSampledAt = nil
    }
}
#endif
