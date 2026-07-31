import Foundation
import Testing

import CerebralCore

/// NIC-126 Increment 2: the per-mode calendar relevance catalog decoded from
/// config/calendar/profiles.json. Maps modes to their `calendarProfile`, names the default mode,
/// and resolves `#[mode]` tag aliases; the default mode's profile is the catch-all.

private let calendarCatalogJSON = Data("""
{
  "schemaVersion": "1.0.0",
  "description": "ignored extra field",
  "defaultMode": "executive",
  "modeProfiles": {
    "executive": "all",
    "developer": "engineering",
    "school": "academic",
    "entertainment": "leisure"
  },
  "tagAliases": {
    "dev": "developer",
    "work": "executive",
    "study": "school"
  }
}
""".utf8)

@Test("the catalog decodes default mode, mode profiles, and tag aliases (ignoring extra fields)")
func calendarCatalogDecodes() throws {
    let catalog = try CalendarProfileCatalog.decode(from: calendarCatalogJSON)
    #expect(catalog.defaultMode == "executive")
    #expect(catalog.modeProfiles["developer"] == "engineering")
    #expect(catalog.tagAliases["dev"] == "developer")
}

@Test("profile(forMode:) resolves a mode's calendarProfile, and the default mode's is the catch-all")
func calendarCatalogProfiles() throws {
    let catalog = try CalendarProfileCatalog.decode(from: calendarCatalogJSON)
    #expect(catalog.profile(forMode: "developer") == "engineering")
    #expect(catalog.profile(forMode: "executive") == "all")
    #expect(catalog.profile(forMode: "nope") == nil)
    #expect(catalog.catchAllProfile == "all")
}

@Test("mode(forTag:) resolves an alias, a raw mode id, and is case-insensitive; unknown is nil")
func calendarCatalogTagResolution() throws {
    let catalog = try CalendarProfileCatalog.decode(from: calendarCatalogJSON)
    #expect(catalog.mode(forTag: "dev") == "developer")
    #expect(catalog.mode(forTag: "DEV") == "developer")
    // A raw mode id used directly as a tag resolves even without an alias entry.
    #expect(catalog.mode(forTag: "school") == "school")
    #expect(catalog.mode(forTag: "unknown") == nil)
}

@Test("load reads <configDirectory>/calendar/profiles.json, and returns nil when absent")
func calendarCatalogLoadsFromConfigDirectory() throws {
    let configDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("calendar-catalog-test-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: configDir) }

    // Missing file → nil (caller degrades honestly, never crashes).
    #expect(CalendarProfileCatalog.load(configDirectory: configDir) == nil)

    let calendarDir = configDir.appendingPathComponent("calendar", isDirectory: true)
    try FileManager.default.createDirectory(at: calendarDir, withIntermediateDirectories: true)
    try calendarCatalogJSON.write(to: calendarDir.appendingPathComponent("profiles.json"))

    let loaded = try #require(CalendarProfileCatalog.load(configDirectory: configDir))
    #expect(loaded.defaultMode == "executive")
    #expect(loaded.profile(forMode: "developer") == "engineering")
}
