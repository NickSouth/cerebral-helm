import Foundation

/// A disposable, rebuildable on-disk cache of site favicons for pinned URL quick
/// apps (NIC-147). A native app carries its icon inline from disk; a URL has no
/// local icon, so its favicon is fetched from the site (a later increment) and
/// the normalized PNG is cached here, under `<stateRoot>/cache/favicons/`.
///
/// Entries are keyed by a URL's **origin** (scheme + host + optional port), so two
/// references pointing at the same site share one favicon and an entry survives an
/// id or label change. Nothing here is durable user state: deleting the directory
/// only forces a re-fetch, degrading to the placeholder glyph in the meantime
/// (the project's "disposable, rebuildable index" principle). It is therefore kept
/// under `cache/`, apart from `references/` and the other durable state files.
///
/// Two entry kinds live side by side per key:
/// - `<key>.png` — a fetched favicon (a *hit*). Hits do not expire in the MVP;
///   favicons change rarely and a stale icon is harmless.
/// - `<key>.miss` — the epoch-seconds timestamp of the last failed fetch (a
///   *miss*). A miss suppresses re-fetching until `retryAfter` elapses, so an
///   unreachable or favicon-less host is not re-crawled every session.
public struct FaviconCache: Sendable {
    /// How long a recorded miss suppresses another fetch attempt (7 days).
    public static let defaultRetryAfter: TimeInterval = 60 * 60 * 24 * 7

    private let directory: URL
    private let retryAfter: TimeInterval

    public init(directory: URL, retryAfter: TimeInterval = FaviconCache.defaultRetryAfter) {
        self.directory = directory
        self.retryAfter = retryAfter
    }

    // MARK: - Origin normalization

    /// The cache origin for a target URL: `scheme://host[:port]`, lowercased.
    /// Returns `nil` for a non-web (`http`/`https` only) or malformed target, which
    /// is never cached — mirrors the mint/open contracts that only ever handle web
    /// URLs.
    public static func origin(forTarget target: String) -> String? {
        guard
            let components = URLComponents(string: target),
            let scheme = components.scheme?.lowercased(),
            scheme == "http" || scheme == "https",
            let host = components.host?.lowercased(),
            !host.isEmpty
        else { return nil }
        if let port = components.port {
            return "\(scheme)://\(host):\(port)"
        }
        return "\(scheme)://\(host)"
    }

    // MARK: - Reads

    /// The cached favicon PNG for a target, or `nil` when no hit is stored (an
    /// unreadable or absent file degrades to `nil` rather than throwing).
    public func icon(forTarget target: String) -> Data? {
        guard let origin = Self.origin(forTarget: target) else { return nil }
        return try? Data(contentsOf: hitURL(for: origin))
    }

    /// Whether a fetch should be attempted for a target: `true` unless a hit is
    /// stored, or a miss was recorded within the retry window. A malformed / non-web
    /// target never needs a fetch.
    public func needsFetch(forTarget target: String, now: Date = Date()) -> Bool {
        guard let origin = Self.origin(forTarget: target) else { return false }
        if FileManager.default.fileExists(atPath: hitURL(for: origin).path) { return false }
        guard let recordedAt = missTimestamp(for: origin) else { return true }
        return now.timeIntervalSince1970 - recordedAt >= retryAfter
    }

    // MARK: - Writes

    /// Records a fetched favicon, clearing any prior miss for the same origin.
    /// Returns `false` for a non-web target or a write failure (never throws).
    @discardableResult
    public func store(png: Data, forTarget target: String) -> Bool {
        guard let origin = Self.origin(forTarget: target) else { return false }
        ensureDirectory()
        do {
            try png.write(to: hitURL(for: origin), options: .atomic)
            try? FileManager.default.removeItem(at: missURL(for: origin))
            return true
        } catch {
            return false
        }
    }

    /// Records a failed fetch so the origin is not re-crawled until the retry
    /// window elapses. A no-op if a hit is already stored for the origin.
    public func recordMiss(forTarget target: String, now: Date = Date()) {
        guard let origin = Self.origin(forTarget: target) else { return }
        if FileManager.default.fileExists(atPath: hitURL(for: origin).path) { return }
        ensureDirectory()
        let stamp = String(now.timeIntervalSince1970)
        try? stamp.data(using: .utf8)?.write(to: missURL(for: origin), options: .atomic)
    }

    // MARK: - Internals

    private func hitURL(for origin: String) -> URL {
        directory.appendingPathComponent("\(key(for: origin)).png")
    }

    private func missURL(for origin: String) -> URL {
        directory.appendingPathComponent("\(key(for: origin)).miss")
    }

    private func missTimestamp(for origin: String) -> TimeInterval? {
        guard
            let data = try? Data(contentsOf: missURL(for: origin)),
            let text = String(data: data, encoding: .utf8),
            let value = TimeInterval(text.trimmingCharacters(in: .whitespacesAndNewlines))
        else { return nil }
        return value
    }

    private func ensureDirectory() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// A filesystem-safe, stable cache key: the sanitized origin prefixed onto a
    /// deterministic hash of the full origin, so the filename stays inspectable
    /// while distinct origins never collide. Swift's `Hasher` is unusable here — it
    /// is randomly seeded per process — so a fixed FNV-1a hash provides the
    /// cross-process, cross-platform stability a persisted key requires.
    private func key(for origin: String) -> String {
        "\(sanitized(origin))-\(Self.fnv1a(origin))"
    }

    private func sanitized(_ origin: String) -> String {
        let allowed = origin.lowercased().map { character -> Character in
            character.isASCII && (character.isLetter || character.isNumber) ? character : "-"
        }
        return String(allowed.prefix(48))
    }

    /// 64-bit FNV-1a, rendered as fixed-width hex. Deterministic across processes
    /// and platforms (unlike `Hasher`), which a persisted cache key requires.
    static func fnv1a(_ string: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(format: "%016llx", hash)
    }
}
