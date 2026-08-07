// NIC-151: Chrome profile discovery reads Chrome's `Local State` (directory →
// display name + avatar file) so the UI can offer a real-profile dropdown. Driven
// against a temporary Chrome support directory so no real Chrome data is touched.
#if canImport(AppKit)
import AppKit
import Foundation
import Testing

import CerebralMacAdapters

private func makeChromeSupport(
    localState: String, avatars: [String: Bool] = [:]
) throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("chrome-support-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Data(localState.utf8).write(to: root.appendingPathComponent("Local State"))
    // Write a real 2×2 PNG into each requested profile dir so normalization runs.
    let png = smallPNG()
    for (dir, hasAvatar) in avatars where hasAvatar {
        let profileDir = root.appendingPathComponent(dir, isDirectory: true)
        try FileManager.default.createDirectory(at: profileDir, withIntermediateDirectories: true)
        try png.write(to: profileDir.appendingPathComponent("Google Profile Picture.png"))
    }
    return root
}

private func smallPNG() -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    return rep.representation(using: .png, properties: [:])!
}

@Test("discovery reads directory → name and decodes the avatar, Default first")
func discoversProfilesWithAvatars() throws {
    let localState = """
    { "profile": { "info_cache": {
        "Profile 1": { "name": "Work", "gaia_picture_file_name": "Google Profile Picture.png" },
        "Default": { "name": "Nick", "gaia_picture_file_name": "Google Profile Picture.png" }
    } } }
    """
    let support = try makeChromeSupport(localState: localState, avatars: ["Default": true, "Profile 1": true])
    let profiles = MacChromeProfileDiscoveryCapability.enumerate(chromeSupportDirectory: support)

    #expect(profiles.map(\.directory) == ["Default", "Profile 1"]) // Default first
    #expect(profiles.map(\.name) == ["Nick", "Work"])
    #expect(profiles.allSatisfy { $0.iconPNGBase64 != nil }) // avatars decoded
}

@Test("a profile without a picture file carries no avatar; the name falls back to the directory")
func handlesMissingAvatarAndName() throws {
    let localState = """
    { "profile": { "info_cache": {
        "Profile 2": { "name": "" }
    } } }
    """
    let support = try makeChromeSupport(localState: localState)
    let profiles = MacChromeProfileDiscoveryCapability.enumerate(chromeSupportDirectory: support)

    #expect(profiles.count == 1)
    #expect(profiles[0].directory == "Profile 2")
    #expect(profiles[0].name == "Profile 2") // empty display name → directory name
    #expect(profiles[0].iconPNGBase64 == nil)
}

@Test("a missing Local State degrades to an empty list, never an error")
func missingLocalStateIsEmpty() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("chrome-empty-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    #expect(MacChromeProfileDiscoveryCapability.enumerate(chromeSupportDirectory: root).isEmpty)
}

// MARK: - Account → profile (Gmail links open in the profile signed into the account)

/// Shaped like this Mac's real `Local State`: a personal account in `Default` and a school
/// Workspace account in `Profile 1`.
private let twoAccountLocalState = """
{ "profile": { "info_cache": {
    "Default":   { "name": "Nick", "user_name": "nick@gmail.com" },
    "Profile 1": { "name": "Work", "user_name": "nsouthey@umass.edu" }
} } }
"""

@Test("an account resolves to the Chrome profile signed into it")
func resolvesProfileForAccount() throws {
    let support = try makeChromeSupport(localState: twoAccountLocalState)
    #expect(MacChromeProfileDiscoveryCapability.profileDirectory(
        forAccount: "nsouthey@umass.edu", chromeSupportDirectory: support
    ) == "Profile 1")
    #expect(MacChromeProfileDiscoveryCapability.profileDirectory(
        forAccount: "nick@gmail.com", chromeSupportDirectory: support
    ) == "Default")
}

@Test("the address match is case- and whitespace-insensitive")
func resolvesProfileIgnoringCaseAndSpace() throws {
    let support = try makeChromeSupport(localState: twoAccountLocalState)
    // Gmail reports the address in whatever case the account was created with; Chrome stores its
    // own. Matching exactly would send mail to the wrong profile for no visible reason.
    #expect(MacChromeProfileDiscoveryCapability.profileDirectory(
        forAccount: "  NSouthey@UMass.edu ", chromeSupportDirectory: support
    ) == "Profile 1")
}

@Test("an account no profile is signed into resolves to nil rather than a guess")
func unknownAccountResolvesToNil() throws {
    let support = try makeChromeSupport(localState: twoAccountLocalState)
    // Falling back to "Default" here would open one mailbox's links in the other's session.
    #expect(MacChromeProfileDiscoveryCapability.profileDirectory(
        forAccount: "stranger@example.com", chromeSupportDirectory: support
    ) == nil)
    #expect(MacChromeProfileDiscoveryCapability.profileDirectory(
        forAccount: "   ", chromeSupportDirectory: support
    ) == nil)
}

@Test("a profile that is not signed in is never matched")
func signedOutProfileIsNeverMatched() throws {
    let localState = """
    { "profile": { "info_cache": { "Profile 3": { "name": "Guest" } } } }
    """
    let support = try makeChromeSupport(localState: localState)
    #expect(MacChromeProfileDiscoveryCapability.profileDirectory(
        forAccount: "nick@gmail.com", chromeSupportDirectory: support
    ) == nil)
}
#endif
