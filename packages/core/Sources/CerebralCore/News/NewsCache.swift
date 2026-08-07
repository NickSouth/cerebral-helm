import Foundation

/// Why a cached profile has no headlines. Persisted as a string so the stored row stays
/// inspectable and a future case can be added without breaking older rows (an unknown value
/// simply fails to decode and degrades to "no cache yet").
public enum NewsCacheFailure: String, Codable, Equatable, Sendable {
    /// The API credential was unbound or rejected at the last attempt — the panel guides the user
    /// to add it.
    case credentialsMissing
    /// Every source was rate-limited or out of quota at the last attempt.
    case rateLimited
    /// The provider or network failed at the last attempt and there was no prior good result.
    case unavailable
}

/// One relevance profile's last known news result (the quota fix, NIC-127 follow-up).
///
/// `headlines` is the last **successful** fetch — it is deliberately *not* cleared by a later
/// provider/network failure, so a rate-limited or offline tick keeps showing real headlines
/// instead of blanking the panel. `fetchedAt` is when those headlines were retrieved (not when
/// they were last re-emitted), which is what bounds how long they may be served.
/// `failure` is non-nil only when there is nothing good to show.
public struct NewsCacheEntry: Codable, Equatable, Sendable {
    /// The last successfully fetched headlines; empty when `failure` is set.
    public let headlines: [NewsHeadline]
    /// The failure to render when `headlines` is empty; nil when the entry holds real headlines.
    public let failure: NewsCacheFailure?
    /// When `headlines` were fetched (or when the failure was observed).
    public let fetchedAt: Date

    public init(headlines: [NewsHeadline], failure: NewsCacheFailure? = nil, fetchedAt: Date) {
        self.headlines = headlines
        self.failure = failure
        self.fetchedAt = fetchedAt
    }
}

/// The persisted news cache: every profile's last known result plus when the publisher last
/// *attempted* a network fetch.
///
/// `lastAttemptAt` — not "last success" — is what the minimum-fetch-interval floor is measured
/// from, so a provider that keeps failing (a 429, a dead network) is not hammered once per
/// occlusion flap or app relaunch. It is a single value rather than one per profile because the
/// publisher fetches every profile in the same tick.
public struct NewsCacheSnapshot: Codable, Equatable, Sendable {
    /// newsProfile → its last known result.
    public var entries: [String: NewsCacheEntry]
    /// When a network fetch was last attempted, regardless of outcome; nil when never.
    public var lastAttemptAt: Date?

    public init(entries: [String: NewsCacheEntry] = [:], lastAttemptAt: Date? = nil) {
        self.entries = entries
        self.lastAttemptAt = lastAttemptAt
    }
}

/// Port for the durable news cache. The concrete SQLite adapter lives in the storage package
/// (operational state under the state root, ADR-006).
///
/// This is **rebuildable derived state**: losing it costs one extra provider request, never user
/// data, so every failure degrades to "no cache yet" rather than surfacing an error.
public protocol NewsCacheStore: Sendable {
    /// The stored cache, or nil when nothing has been cached yet.
    func load() throws -> NewsCacheSnapshot?
    /// Replaces the stored cache wholesale.
    func save(_ snapshot: NewsCacheSnapshot) throws
}

/// A process-local ``NewsCacheStore`` for tests and for hosts with no operational database.
public final class InMemoryNewsCacheStore: NewsCacheStore, @unchecked Sendable {
    private let lock = NSLock()
    private var snapshot: NewsCacheSnapshot?

    public init(snapshot: NewsCacheSnapshot? = nil) {
        self.snapshot = snapshot
    }

    public func load() throws -> NewsCacheSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        return snapshot
    }

    public func save(_ snapshot: NewsCacheSnapshot) throws {
        lock.lock()
        defer { lock.unlock() }
        self.snapshot = snapshot
    }
}
