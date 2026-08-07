// Read-only Google Chrome profile discovery (NIC-151 follow-up). Chrome records
// its profiles in `Local State` (a JSON file under the user's Chrome support
// directory): `profile.info_cache` maps each on-disk directory name to its
// display name and an optional avatar file. We read that map and each profile's
// `Google Profile Picture.png`, so the UI can offer a dropdown of real profiles
// (display name shown, directory name stored as the `--profile-directory` value)
// and badge tiles with the profile avatar.
//
// This never launches Chrome and never writes — it only reads Chrome's own
// metadata and image files. Compiled empty off Apple platforms so the package
// graph still builds on Linux CI.
#if canImport(AppKit)
import AppKit
import Foundation
import CerebralTools

public struct MacChromeProfileDiscoveryCapability: ChromeProfileDiscoveryCapability {
    /// Avatar raster size: crisp on a small corner badge without a heavy payload.
    private static let avatarPixelSize = 48
    /// Per-avatar base64 cap, matching the app-icon budget headroom.
    private static let avatarBase64Cap = 98304

    /// The Chrome support directory (`~/Library/Application Support/Google/Chrome`),
    /// overridable for tests.
    private let chromeSupportDirectory: URL

    /// Chrome's standard support directory on this Mac.
    public static var defaultSupportDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Google/Chrome", isDirectory: true)
    }

    public init(chromeSupportDirectory: URL? = nil) {
        self.chromeSupportDirectory = chromeSupportDirectory ?? Self.defaultSupportDirectory
    }

    public func listProfiles() async throws -> [ChromeProfile] {
        Self.enumerate(chromeSupportDirectory: chromeSupportDirectory)
    }

    /// The profile directory signed into `account`, or nil when no profile is.
    ///
    /// Chrome's `info_cache` records each profile's signed-in address under `user_name`, so the
    /// mapping from a Google account to the Chrome profile that holds it is **already on disk** —
    /// which is why opening mail in the right profile needs no setting and nothing for the user to
    /// keep in sync. Sign into a new account in a new profile and the link follows it.
    ///
    /// Deliberately **not** exposed through ``ChromeProfileDiscoveryCapability``: that capability
    /// feeds the dashboard's profile picker over the bridge, and the addresses have no business
    /// crossing into the web layer to populate a dropdown that shows display names.
    public static func profileDirectory(
        forAccount account: String, chromeSupportDirectory: URL
    ) -> String? {
        let wanted = account.trimmingCharacters(in: .whitespaces).lowercased()
        guard !wanted.isEmpty else { return nil }
        let matches = infoCache(chromeSupportDirectory: chromeSupportDirectory)
            .filter { (($0.value as? [String: Any])?["user_name"] as? String)?.lowercased() == wanted }
            .keys
        // Sorted so two profiles signed into the same account resolve to the same one every time
        // rather than whichever the dictionary happened to yield.
        return matches.sorted().first
    }

    /// Chrome's profile directory → info map, or empty when `Local State` is missing/unreadable.
    private static func infoCache(chromeSupportDirectory: URL) -> [String: Any] {
        let localState = chromeSupportDirectory.appendingPathComponent("Local State", isDirectory: false)
        guard
            let data = try? Data(contentsOf: localState),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let profile = root["profile"] as? [String: Any],
            let infoCache = profile["info_cache"] as? [String: Any]
        else {
            return [:]
        }
        return infoCache
    }

    /// The synchronous enumeration core. A missing or unreadable `Local State`
    /// degrades to an empty list (Chrome not installed / never launched) rather
    /// than failing — the dropdown just shows no profiles.
    public static func enumerate(chromeSupportDirectory: URL) -> [ChromeProfile] {
        let infoCache = Self.infoCache(chromeSupportDirectory: chromeSupportDirectory)

        var profiles: [ChromeProfile] = []
        for (directory, value) in infoCache {
            guard let info = value as? [String: Any] else { continue }
            // Chrome falls back to the directory name when no display name is set.
            let name = (info["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? directory
            let avatar = Self.avatarBase64(
                chromeSupportDirectory: chromeSupportDirectory,
                directory: directory,
                pictureFileName: info["gaia_picture_file_name"] as? String
            )
            profiles.append(ChromeProfile(directory: directory, name: name, iconPNGBase64: avatar))
        }

        // "Default" first (Chrome's primary profile), then the rest by display name
        // — a stable, predictable order for the dropdown and picker.
        return profiles.sorted { lhs, rhs in
            if lhs.directory == "Default" { return rhs.directory != "Default" }
            if rhs.directory == "Default" { return false }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    /// The profile's account picture as a small base64 PNG, or nil when there is
    /// no picture file or it cannot be rendered / would exceed the size cap.
    private static func avatarBase64(
        chromeSupportDirectory: URL, directory: String, pictureFileName: String?
    ) -> String? {
        guard let pictureFileName, !pictureFileName.isEmpty else { return nil }
        let pictureURL = chromeSupportDirectory
            .appendingPathComponent(directory, isDirectory: true)
            .appendingPathComponent(pictureFileName, isDirectory: false)
        guard
            FileManager.default.fileExists(atPath: pictureURL.path),
            let image = NSImage(contentsOf: pictureURL)
        else { return nil }
        return normalize(image)
    }

    /// Redraws an avatar image to a fixed square PNG, size-capped. Shared shape
    /// with the app-icon normalizer so the payloads stay small and predictable.
    private static func normalize(_ image: NSImage) -> String? {
        let pixels = avatarPixelSize
        let size = NSSize(width: pixels, height: pixels)
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        bitmap.size = size

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        NSGraphicsContext.current = context
        image.draw(in: NSRect(origin: .zero, size: size))
        context.flushGraphics()

        guard let png = bitmap.representation(using: .png, properties: [:]) else { return nil }
        let base64 = png.base64EncodedString()
        return base64.count <= avatarBase64Cap ? base64 : nil
    }
}
#endif
