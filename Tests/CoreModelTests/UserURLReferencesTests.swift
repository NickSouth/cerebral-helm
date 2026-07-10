import Foundation
import Testing

import CerebralCore

/// NIC-146: a user-added URL becomes a minted reference the same way a discovered
/// app does, so it can be pinned as a per-mode quick app. Minting is http/https
/// only, idempotent by target, and globally id-unique so `open <id>` never
/// resolves ambiguously between a URL and an app reference.

private func temporaryStateRoot() throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("user-urls-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

@Test("adding a URL mints a durable reference that reloads")
func addMintsDurableReference() throws {
    let stateRoot = try temporaryStateRoot()
    let result = UserURLReferences.add(
        url: "https://news.ycombinator.com", label: "Hacker News",
        existingIDs: [], stateRoot: stateRoot
    )
    let entry = try #require(try result.get())
    #expect(entry.id == "hacker-news")
    #expect(entry.label == "Hacker News")
    #expect(entry.target == "https://news.ycombinator.com")
    #expect(UserURLReferences.load(stateRoot: stateRoot) == [entry])
}

@Test("a scheme-less host defaults to https; the label falls back to the host")
func schemelessHostDefaultsToHTTPS() throws {
    let stateRoot = try temporaryStateRoot()
    let entry = try UserURLReferences.add(
        url: "github.com", label: nil, existingIDs: [], stateRoot: stateRoot
    ).get()
    #expect(entry.target == "https://github.com")
    #expect(entry.label == "github.com")
    #expect(entry.id == "github-com")
}

@Test("adding the same URL twice is idempotent by target — no duplicate")
func addIsIdempotentByTarget() throws {
    let stateRoot = try temporaryStateRoot()
    let first = try UserURLReferences.add(
        url: "https://example.com/docs", label: "Docs", existingIDs: [], stateRoot: stateRoot
    ).get()
    // A different label, but the same target: returns the existing entry, mints nothing.
    let second = try UserURLReferences.add(
        url: "https://example.com/docs", label: "Something else", existingIDs: [], stateRoot: stateRoot
    ).get()
    #expect(second == first)
    #expect(UserURLReferences.load(stateRoot: stateRoot).count == 1)
}

@Test("a minted id is deduplicated against every known reference id, apps included")
func mintedIDsAvoidCrossCatalogCollision() throws {
    let stateRoot = try temporaryStateRoot()
    // "github" is already taken (say, by an app reference or a shipped URL).
    let entry = try UserURLReferences.add(
        url: "https://github.com", label: "GitHub", existingIDs: ["github"], stateRoot: stateRoot
    ).get()
    #expect(entry.id == "github-2")
    #expect(entry.id.range(of: "^[a-z][a-z0-9-]*$", options: .regularExpression) != nil)
}

@Test("only http and https mint — never file, custom, or javascript schemes")
func onlyWebSchemesMint() throws {
    let stateRoot = try temporaryStateRoot()
    #expect(UserURLReferences.add(url: "", label: nil, existingIDs: [], stateRoot: stateRoot)
        == .failure(.emptyURL))
    #expect(UserURLReferences.add(url: "file:///etc/passwd", label: nil, existingIDs: [], stateRoot: stateRoot)
        == .failure(.unsupportedScheme))
    #expect(UserURLReferences.add(url: "javascript:alert(1)", label: nil, existingIDs: [], stateRoot: stateRoot)
        == .failure(.unsupportedScheme))
    // Nothing was persisted by any rejected add.
    #expect(UserURLReferences.load(stateRoot: stateRoot).isEmpty)
}

@Test("the reference loader merges minted URLs; shipped wins on id and target")
func loaderMergesUserURLReferences() throws {
    let stateRoot = try temporaryStateRoot()
    // The repository config ships github → https://github.com and docs.
    let configDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("config", isDirectory: true)

    UserURLReferences.add(
        url: "https://news.ycombinator.com", label: "Hacker News",
        existingIDs: [], stateRoot: stateRoot
    )
    // Same target as the shipped github reference — must not re-add or shadow it.
    UserURLReferences.add(
        url: "https://github.com", label: "My GitHub", existingIDs: [], stateRoot: stateRoot
    )

    let merged = try ReferenceCatalogLoader.load(configDirectory: configDirectory, stateRoot: stateRoot)
    #expect(merged.urls["hacker-news"]?.target == "https://news.ycombinator.com")
    #expect(merged.urls["github"]?.label == "GitHub")
    #expect(merged.urls.values.filter { $0.target == "https://github.com" }.count == 1)
}
