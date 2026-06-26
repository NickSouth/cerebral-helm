import Foundation

/// Injectable wall-clock time source for the command spine.
///
/// Named `TimeSource` rather than `Clock` to avoid colliding with the Swift
/// standard library `Clock` protocol. Production code uses ``SystemClock``;
/// tests, fixtures, and simulations use ``FixedClock`` so lifecycle timestamps
/// are deterministic (PRD NFR-04).
public protocol TimeSource: Sendable {
    /// The current instant. Implementations may advance on each call.
    func now() -> Date
}

/// Real wall-clock time.
public struct SystemClock: TimeSource {
    public init() {}

    public func now() -> Date { Date() }
}

/// Deterministic time source.
///
/// Returns a fixed instant, optionally advancing by `step` seconds on every
/// call so a sequence of events receives distinct, predictable timestamps.
public final class FixedClock: TimeSource, @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    private let step: TimeInterval

    /// - Parameters:
    ///   - instant: The first instant returned by ``now()``.
    ///   - step: Seconds added after each call. `0` keeps the clock frozen.
    public init(_ instant: Date, step: TimeInterval = 0) {
        self.current = instant
        self.step = step
    }

    public func now() -> Date {
        lock.lock()
        defer { lock.unlock() }
        let value = current
        current = current.addingTimeInterval(step)
        return value
    }
}
