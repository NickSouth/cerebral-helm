import Foundation

/// A thread-safe, in-memory record of which URL references CerebralHelm opened in
/// which mode this session (NIC-145).
///
/// It is what scopes tab surfacing to "opened by CH in the current mode": the URL
/// adapter only *attempts* to focus an existing browser tab for a `(modeID, urlID)`
/// pair it previously recorded here — never for a URL the user opened themselves,
/// nor for one CH opened in a different mode.
///
/// Session-only by design (owner decision, NIC-145): CH cannot observe whether a
/// browser tab still exists, so a record persisted across a relaunch could not be
/// trusted. Losing the record on restart simply means the next trigger opens fresh
/// — the honest fallback, never a wrong surface.
public final class SessionURLOpenRegistry: @unchecked Sendable {
    private struct Key: Hashable {
        let modeID: String
        let urlID: String
    }

    private let lock = NSLock()
    private var opened: Set<Key> = []

    public init() {}

    /// Records that CH opened `urlID` in `modeID`.
    public func record(modeID: String, urlID: String) {
        lock.lock()
        defer { lock.unlock() }
        opened.insert(Key(modeID: modeID, urlID: urlID))
    }

    /// Whether CH already opened `urlID` in `modeID` this session.
    public func contains(modeID: String, urlID: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return opened.contains(Key(modeID: modeID, urlID: urlID))
    }
}
