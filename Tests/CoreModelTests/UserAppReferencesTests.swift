import Foundation
import Testing

import CerebralCore

/// NIC-119 (owner decision, 2026-07-06): every discovered application without a
/// configured reference gets one minted automatically into the user catalog.

private func temporaryStateRoot() throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("user-refs-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

@Test("minting creates references only for unreferenced targets, idempotently")
func mintingIsTargetedAndIdempotent() throws {
    let stateRoot = try temporaryStateRoot()
    let shipped = [ReferenceEntry(id: "vscode", label: "Visual Studio Code", target: "com.microsoft.VSCode")]
    let discovered = [
        UserAppReferences.DiscoveredApp(bundleID: "com.microsoft.VSCode", name: "Visual Studio Code"),
        UserAppReferences.DiscoveredApp(bundleID: "com.spotify.client", name: "Spotify"),
    ]

    let first = UserAppReferences.mint(discovered: discovered, shipped: shipped, stateRoot: stateRoot)
    #expect(first.map(\.id) == ["spotify"])
    #expect(first.first?.target == "com.spotify.client")

    // Re-minting the same discovery changes nothing — ids stay stable.
    let second = UserAppReferences.mint(discovered: discovered, shipped: shipped, stateRoot: stateRoot)
    #expect(second == first)

    // The file is durable and reloads.
    #expect(UserAppReferences.load(stateRoot: stateRoot) == first)
}

@Test("minted ids are valid config-id slugs, deduplicated against every known id")
func mintedIDsAreValidAndUnique() throws {
    let stateRoot = try temporaryStateRoot()
    let shipped = [ReferenceEntry(id: "spotify", label: "Spotify", target: "com.other.Spotify")]
    let discovered = [
        UserAppReferences.DiscoveredApp(bundleID: "com.spotify.client", name: "Spotify"),
        UserAppReferences.DiscoveredApp(bundleID: "com.example.numbers", name: "1Password 8"),
        UserAppReferences.DiscoveredApp(bundleID: "com.example.symbols", name: "!!!"),
    ]

    let minted = UserAppReferences.mint(discovered: discovered, shipped: shipped, stateRoot: stateRoot)
    let ids = minted.map(\.id)
    // Shipped already owns "spotify" (different target), so the clash dedupes.
    #expect(ids.contains("spotify-2"))
    for id in ids {
        #expect(id.range(of: "^[a-z][a-z0-9-]*$", options: .regularExpression) != nil, Comment(rawValue: id))
    }
    #expect(Set(ids).count == ids.count)
}

@Test("the reference loader merges minted apps; shipped wins on id and target")
func loaderMergesUserReferences() throws {
    let stateRoot = try temporaryStateRoot()
    // The repository config directory has vscode/terminal/xcode/claude-desktop.
    let configDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("config", isDirectory: true)
    let shipped = try ReferenceCatalogLoader.load(configDirectory: configDirectory)

    UserAppReferences.mint(
        discovered: [
            UserAppReferences.DiscoveredApp(bundleID: "com.spotify.client", name: "Spotify"),
            // Already shipped (same target) — must not re-mint or shadow.
            UserAppReferences.DiscoveredApp(bundleID: "com.microsoft.VSCode", name: "VS Code Clone"),
        ],
        shipped: Array(shipped.apps.values),
        stateRoot: stateRoot
    )

    let merged = try ReferenceCatalogLoader.load(configDirectory: configDirectory, stateRoot: stateRoot)
    #expect(merged.apps["spotify"]?.target == "com.spotify.client")
    #expect(merged.apps["vscode"]?.label == "Visual Studio Code")
    #expect(merged.apps.values.filter { $0.target == "com.microsoft.VSCode" }.count == 1)
}
