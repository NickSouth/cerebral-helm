// NIC-119: read-only application discovery on the live macOS host.
#if canImport(AppKit)
import Foundation
import Testing

import CerebralMacAdapters
import CerebralTools

@Test("live discovery enumerates installed apps: unique bundle ids, non-empty names, capped decodable icons")
func liveDiscoveryShape() async throws {
    let result = try await MacAppDiscoveryCapability().listApplications(includeIcons: true)

    // Every macOS host ships /System/Applications — an empty result is a bug.
    #expect(!result.apps.isEmpty)
    let ids = result.apps.map(\.bundleID)
    #expect(Set(ids).count == ids.count)
    for app in result.apps {
        #expect(!app.name.isEmpty)
        #expect(!app.bundleID.isEmpty)
    }
    // Icons (sampled — rendering all is slow) decode as data and respect the cap.
    for app in result.apps.prefix(10) {
        if let icon = app.iconPNGBase64 {
            #expect(icon.count <= 98304)
            #expect(Data(base64Encoded: icon) != nil)
        }
    }
}

@Test("discovery without icons carries none, and never launches anything")
func discoveryWithoutIcons() async throws {
    let result = try await MacAppDiscoveryCapability().listApplications(includeIcons: false)
    #expect(result.apps.allSatisfy { $0.iconPNGBase64 == nil })
}

@Test("the live scan finds apps macOS keeps in Utilities, not only the top level (NIC-175)")
func liveDiscoveryFindsSystemUtilities() async throws {
    // macOS ships ~56 apps in /System/Applications/Utilities — Terminal, Activity Monitor, Console,
    // Disk Utility. A top-level-only scan missed every one of them permanently, so they could
    // neither be opened by id nor pinned. These two ship on every macOS install.
    let result = try await MacAppDiscoveryCapability().listApplications(includeIcons: false)
    let ids = Set(result.apps.map(\.bundleID))
    #expect(ids.contains("com.apple.Terminal"))
    #expect(ids.contains("com.apple.ActivityMonitor"))
}

// MARK: - Nested application folders (NIC-175)

/// Writes a minimal but real `.app` — an `Info.plist` with a bundle identifier is all `Bundle(url:)`
/// needs to load, which is exactly the gate discovery applies.
private func makeApp(at url: URL, bundleID: String) throws {
    let contents = url.appendingPathComponent("Contents", isDirectory: true)
    try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
    let plist: [String: Any] = ["CFBundleIdentifier": bundleID, "CFBundleName": url.deletingPathExtension().lastPathComponent]
    let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    try data.write(to: contents.appendingPathComponent("Info.plist"))
}

private func withTemporaryRoot(_ body: (URL) throws -> Void) throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("ch-appdiscovery-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try body(root)
}

@Test("apps in a nested folder are discovered, not just the top level (NIC-175)")
func discoversNestedApps() throws {
    try withTemporaryRoot { root in
        // The shapes that occur in practice: top level, `Utilities/` (one level down, where macOS
        // itself puts Terminal), and a vendor suite folder (two levels down).
        try makeApp(at: root.appendingPathComponent("Top.app"), bundleID: "test.top")
        let utilities = root.appendingPathComponent("Utilities", isDirectory: true)
        try FileManager.default.createDirectory(at: utilities, withIntermediateDirectories: true)
        try makeApp(at: utilities.appendingPathComponent("Nested.app"), bundleID: "test.nested")
        let suite = root.appendingPathComponent("Vendor/Suite", isDirectory: true)
        try FileManager.default.createDirectory(at: suite, withIntermediateDirectories: true)
        try makeApp(at: suite.appendingPathComponent("Deep.app"), bundleID: "test.deep")

        let result = MacAppDiscoveryCapability.enumerate(searchDirectories: [root], includeIcons: false)
        #expect(Set(result.apps.map(\.bundleID)) == ["test.top", "test.nested", "test.deep"])
    }
}

@Test("helper apps inside a bundle are never listed as installed applications")
func neverDescendsIntoBundles() throws {
    try withTemporaryRoot { root in
        let host = root.appendingPathComponent("Host.app")
        try makeApp(at: host, bundleID: "test.host")
        // The shape every real browser and IDE ships: helper executables nested in Contents. They
        // are implementation details — listing them would bury the real apps and mint junk
        // references for things a user never launches.
        let helpers = host.appendingPathComponent("Contents/Frameworks", isDirectory: true)
        try FileManager.default.createDirectory(at: helpers, withIntermediateDirectories: true)
        try makeApp(at: helpers.appendingPathComponent("Host Helper.app"), bundleID: "test.host.helper")

        let result = MacAppDiscoveryCapability.enumerate(searchDirectories: [root], includeIcons: false)
        #expect(result.apps.map(\.bundleID) == ["test.host"])
    }
}

@Test("the depth bound stops the scan rather than walking the whole tree")
func respectsDepthBound() throws {
    try withTemporaryRoot { root in
        let tooDeep = root.appendingPathComponent("a/b/c", isDirectory: true)
        try FileManager.default.createDirectory(at: tooDeep, withIntermediateDirectories: true)
        try makeApp(at: tooDeep.appendingPathComponent("TooDeep.app"), bundleID: "test.toodeep")

        // Discovery runs on every picker open, so the bound is deliberate: an app buried three
        // levels down is out of scope, not an oversight.
        let result = MacAppDiscoveryCapability.enumerate(searchDirectories: [root], includeIcons: false)
        #expect(result.apps.isEmpty)
    }
}

@Test("an incomplete bundle is skipped — a half-copied app is not listed")
func skipsIncompleteBundles() throws {
    try withTemporaryRoot { root in
        try makeApp(at: root.appendingPathComponent("Good.app"), bundleID: "test.good")
        // A large app mid-copy: the directory exists but Info.plist has not landed yet, so
        // `Bundle(url:)` cannot load it. Listing it would show an entry that cannot be opened.
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Copying.app/Contents", isDirectory: true),
            withIntermediateDirectories: true
        )

        let result = MacAppDiscoveryCapability.enumerate(searchDirectories: [root], includeIcons: false)
        #expect(result.apps.map(\.bundleID) == ["test.good"])
    }
}

@Test("an unreadable subdirectory costs only itself, not the whole scan")
func unreadableDirectoryDegrades() throws {
    try withTemporaryRoot { root in
        try makeApp(at: root.appendingPathComponent("Visible.app"), bundleID: "test.visible")
        let locked = root.appendingPathComponent("Locked", isDirectory: true)
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try makeApp(at: locked.appendingPathComponent("Hidden.app"), bundleID: "test.hidden")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }

        let result = MacAppDiscoveryCapability.enumerate(searchDirectories: [root], includeIcons: false)
        #expect(result.apps.map(\.bundleID) == ["test.visible"])
    }
}
#endif
