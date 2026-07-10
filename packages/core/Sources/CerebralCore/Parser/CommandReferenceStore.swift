import Foundation

/// A thread-safe, reloadable holder for the resolved ``CommandReferences`` (NIC-146).
///
/// The reference catalog is composed once at startup, but a user can mint a new URL
/// (or app) reference mid-session. Both the parser (`open <id>` resolution) and the
/// native app/url capability target maps read the catalog through this one shared
/// box, so a single ``reload(_:)`` after a mint makes the new reference resolvable
/// everywhere — no relaunch. Mirrors the ``PolicyOverridesBox`` live-re-arm pattern
/// (NIC-137): compose the readers over the box once, then swap its contents.
public final class CommandReferenceStore: @unchecked Sendable {
    private let lock = NSLock()
    private var value: CommandReferences

    public init(_ references: CommandReferences) {
        self.value = references
    }

    /// The current catalog snapshot.
    public var current: CommandReferences {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    /// Replaces the catalog atomically; every reader sees the new snapshot on its
    /// next access.
    public func reload(_ references: CommandReferences) {
        lock.lock()
        defer { lock.unlock() }
        value = references
    }
}
