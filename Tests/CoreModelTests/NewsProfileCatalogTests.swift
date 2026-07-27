import Foundation
import Testing

import CerebralCore

/// NIC-127 Increment 5: the per-mode news relevance catalog decoded from config/news/profiles.json.
/// Maps a mode's `newsProfile` to provider categories; an unmapped profile falls back to the
/// default so a mode always resolves to some news.

private let newsCatalogJSON = Data("""
{
  "schemaVersion": "1.0.0",
  "description": "ignored extra field",
  "language": "en",
  "defaultCategory": "top",
  "profiles": {
    "broad": "top,business,technology",
    "engineering": "technology"
  }
}
""".utf8)

@Test("the catalog decodes language, default, and profile mappings (ignoring extra fields)")
func newsCatalogDecodes() throws {
    let catalog = try NewsProfileCatalog.decode(from: newsCatalogJSON)
    #expect(catalog.language == "en")
    #expect(catalog.defaultCategory == "top")
    #expect(catalog.profiles["broad"] == "top,business,technology")
}

@Test("a mapped profile resolves to its categories")
func newsCatalogMapsKnownProfile() throws {
    let catalog = try NewsProfileCatalog.decode(from: newsCatalogJSON)
    #expect(catalog.category(for: "broad") == "top,business,technology")
    #expect(catalog.category(for: "engineering") == "technology")
}

@Test("an unmapped profile falls back to the default category, never nil")
func newsCatalogFallsBackToDefault() throws {
    let catalog = try NewsProfileCatalog.decode(from: newsCatalogJSON)
    #expect(catalog.category(for: "does-not-exist") == "top")
}

@Test("load reads <configDirectory>/news/profiles.json, and returns nil when absent")
func newsCatalogLoadsFromConfigDirectory() throws {
    let configDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("news-catalog-test-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: configDir) }

    // Missing file → nil (caller degrades honestly, never crashes).
    #expect(NewsProfileCatalog.load(configDirectory: configDir) == nil)

    let newsDir = configDir.appendingPathComponent("news", isDirectory: true)
    try FileManager.default.createDirectory(at: newsDir, withIntermediateDirectories: true)
    try newsCatalogJSON.write(to: newsDir.appendingPathComponent("profiles.json"))

    let loaded = try #require(NewsProfileCatalog.load(configDirectory: configDir))
    #expect(loaded.category(for: "broad") == "top,business,technology")
    #expect(loaded.language == "en")
}
