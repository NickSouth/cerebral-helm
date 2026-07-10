import Foundation
import Testing

import CerebralCore

/// NIC-147 Increment 1: a disposable, origin-keyed on-disk cache of URL-quick-app
/// favicons under `<stateRoot>/cache/favicons`. It stores fetched PNGs (hits),
/// suppresses re-fetching a failing origin within a retry window (misses), and
/// degrades to "no icon / needs fetch" rather than throwing.

private func temporaryCacheDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("favicon-cache-\(UUID().uuidString)", isDirectory: true)
    // Deliberately not created up front: the cache must create its own directory.
    return directory
}

private let samplePNG = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) // PNG magic

@Test("a cold cache reports needs-fetch and returns no icon")
func coldCacheNeedsFetch() throws {
    let cache = FaviconCache(directory: try temporaryCacheDirectory())
    #expect(cache.icon(forTarget: "https://github.com") == nil)
    #expect(cache.needsFetch(forTarget: "https://github.com"))
}

@Test("a stored favicon round-trips and stops needing a fetch")
func hitRoundTrips() throws {
    let cache = FaviconCache(directory: try temporaryCacheDirectory())
    #expect(cache.store(png: samplePNG, forTarget: "https://github.com"))
    #expect(cache.icon(forTarget: "https://github.com") == samplePNG)
    #expect(!cache.needsFetch(forTarget: "https://github.com"))
}

@Test("two targets sharing an origin share one cached favicon")
func originDedupesAcrossTargets() throws {
    let cache = FaviconCache(directory: try temporaryCacheDirectory())
    // Different paths, same scheme+host → same origin → one entry.
    cache.store(png: samplePNG, forTarget: "https://github.com/anthropics")
    #expect(cache.icon(forTarget: "https://github.com/openai/whatever") == samplePNG)
    #expect(!cache.needsFetch(forTarget: "https://github.com"))
    // A different host is a different origin and stays cold.
    #expect(cache.needsFetch(forTarget: "https://gitlab.com"))
}

@Test("a recorded miss suppresses re-fetch until the retry window elapses")
func missSuppressesThenExpires() throws {
    let retryAfter: TimeInterval = 60 * 60 // 1 hour
    let cache = FaviconCache(directory: try temporaryCacheDirectory(), retryAfter: retryAfter)
    let failedAt = Date(timeIntervalSince1970: 1_000_000)

    cache.recordMiss(forTarget: "https://example.com", now: failedAt)
    // Within the window: do not re-crawl.
    #expect(!cache.needsFetch(forTarget: "https://example.com", now: failedAt.addingTimeInterval(60)))
    // Just before the window closes: still suppressed.
    #expect(!cache.needsFetch(forTarget: "https://example.com", now: failedAt.addingTimeInterval(retryAfter - 1)))
    // Once the window elapses: eligible again.
    #expect(cache.needsFetch(forTarget: "https://example.com", now: failedAt.addingTimeInterval(retryAfter + 1)))
    // A miss stores no icon.
    #expect(cache.icon(forTarget: "https://example.com") == nil)
}

@Test("storing a favicon clears a prior miss")
func storeClearsMiss() throws {
    let cache = FaviconCache(directory: try temporaryCacheDirectory(), retryAfter: 60 * 60)
    let failedAt = Date(timeIntervalSince1970: 2_000_000)
    cache.recordMiss(forTarget: "https://example.com", now: failedAt)

    cache.store(png: samplePNG, forTarget: "https://example.com")
    #expect(cache.icon(forTarget: "https://example.com") == samplePNG)
    // Even long after the failure, a hit means no fetch is needed.
    #expect(!cache.needsFetch(forTarget: "https://example.com", now: failedAt.addingTimeInterval(10 * 60 * 60)))
}

@Test("recording a miss is a no-op once a favicon is stored")
func missDoesNotOverwriteHit() throws {
    let cache = FaviconCache(directory: try temporaryCacheDirectory(), retryAfter: 60 * 60)
    cache.store(png: samplePNG, forTarget: "https://example.com")
    cache.recordMiss(forTarget: "https://example.com", now: Date(timeIntervalSince1970: 3_000_000))
    #expect(cache.icon(forTarget: "https://example.com") == samplePNG)
    #expect(!cache.needsFetch(forTarget: "https://example.com"))
}

@Test("non-web and malformed targets are never cached or fetched")
func nonWebTargetsAreInert() throws {
    let cache = FaviconCache(directory: try temporaryCacheDirectory())
    for target in ["file:///etc/passwd", "javascript:alert(1)", "not a url", ""] {
        #expect(FaviconCache.origin(forTarget: target) == nil)
        #expect(!cache.store(png: samplePNG, forTarget: target))
        #expect(cache.icon(forTarget: target) == nil)
        #expect(!cache.needsFetch(forTarget: target))
        cache.recordMiss(forTarget: target) // must not throw or crash
    }
}

@Test("origin normalization lowercases and keeps distinct scheme/host/port apart")
func originNormalization() {
    #expect(FaviconCache.origin(forTarget: "HTTPS://GitHub.com/Foo") == "https://github.com")
    #expect(FaviconCache.origin(forTarget: "http://example.com") == "http://example.com")
    #expect(FaviconCache.origin(forTarget: "https://example.com") == "https://example.com")
    #expect(FaviconCache.origin(forTarget: "https://example.com:8443/x") == "https://example.com:8443")
    // Distinct origins do not collide on the same host name.
    #expect(FaviconCache.origin(forTarget: "http://example.com")
        != FaviconCache.origin(forTarget: "https://example.com"))
}

@Test("the workspace exposes the favicon cache under cache/favicons in the state root")
func workspaceExposesFaviconCacheDirectory() throws {
    let paths = try WorkspacePaths.temporary(repositoryRoot: repositoryRoot())
    #expect(paths.faviconCacheDirectory
        == paths.stateRoot
            .appendingPathComponent("cache", isDirectory: true)
            .appendingPathComponent("favicons", isDirectory: true))
}

/// The repository root, three directories up from this test file
/// (`<root>/Tests/CoreModelTests/<file>.swift`).
private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}
