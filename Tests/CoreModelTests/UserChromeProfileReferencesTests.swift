import Foundation
import Testing

import CerebralCore

/// NIC-151: pinning a Chrome profile mints an app reference that opens Chrome in
/// that profile. The entries deliberately share one bundle id across profiles, so
/// they live in their own store keyed by profile directory and merge into the app
/// catalog by id only.

private func temporaryStateRoot() throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("chrome-profiles-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

@Test("pinning a Chrome profile mints a durable Chrome-targeted app reference")
func mintsChromeProfileReference() throws {
    let stateRoot = try temporaryStateRoot()
    let entry = try #require(try UserChromeProfileReferences.add(
        directory: "Profile 1", name: "Work", existingIDs: [], stateRoot: stateRoot
    ).get())
    #expect(entry.id == "chrome-work")
    #expect(entry.label == "Chrome — Work")
    #expect(entry.target == "com.google.Chrome")
    #expect(entry.profile == "Profile 1")
    #expect(UserChromeProfileReferences.load(stateRoot: stateRoot) == [entry])
}

@Test("two profiles share the Chrome bundle id but are distinct references, idempotent by directory")
func distinctPerProfileIdempotentByDirectory() throws {
    let stateRoot = try temporaryStateRoot()
    let work = try #require(try UserChromeProfileReferences.add(
        directory: "Profile 1", name: "Work", existingIDs: [], stateRoot: stateRoot
    ).get())
    let personal = try #require(try UserChromeProfileReferences.add(
        directory: "Default", name: "Personal", existingIDs: [], stateRoot: stateRoot
    ).get())
    #expect(work.id != personal.id)
    #expect(work.target == personal.target) // same bundle id
    #expect(UserChromeProfileReferences.load(stateRoot: stateRoot).count == 2)

    // Re-pinning the same directory returns the existing entry, no duplicate.
    let workAgain = try #require(try UserChromeProfileReferences.add(
        directory: "Profile 1", name: "Work (renamed)", existingIDs: [], stateRoot: stateRoot
    ).get())
    #expect(workAgain.id == work.id)
    #expect(UserChromeProfileReferences.load(stateRoot: stateRoot).count == 2)
}

@Test("an empty or flag-injecting profile directory is refused without minting")
func refusesInvalidDirectory() throws {
    let stateRoot = try temporaryStateRoot()
    #expect(UserChromeProfileReferences.add(directory: "  ", name: nil, existingIDs: [], stateRoot: stateRoot)
        == .failure(.emptyDirectory))
    #expect(UserChromeProfileReferences.add(
        directory: "Default --load-extension=/tmp/evil", name: nil, existingIDs: [], stateRoot: stateRoot
    ) == .failure(.invalidProfile))
    #expect(UserChromeProfileReferences.load(stateRoot: stateRoot).isEmpty)
}

@Test("Chrome-profile references merge into the app catalog by id, sharing the bundle id")
func loaderMergesChromeProfilesIntoApps() throws {
    let stateRoot = try temporaryStateRoot()
    let configDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("config", isDirectory: true)

    UserChromeProfileReferences.add(directory: "Profile 1", name: "Work", existingIDs: [], stateRoot: stateRoot)
    UserChromeProfileReferences.add(directory: "Default", name: "Personal", existingIDs: [], stateRoot: stateRoot)

    let merged = try ReferenceCatalogLoader.load(configDirectory: configDirectory, stateRoot: stateRoot)
    #expect(merged.apps["chrome-work"]?.profile == "Profile 1")
    #expect(merged.apps["chrome-personal"]?.profile == "Default")
    // Both share the bundle id — the id-only merge kept them distinct.
    #expect(merged.apps.values.filter { $0.target == "com.google.Chrome" }.count == 2)
}
