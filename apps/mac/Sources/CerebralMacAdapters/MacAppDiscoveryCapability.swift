// Read-only application discovery (NIC-119, FR-TOL-04).
#if canImport(AppKit)
import AppKit
import Foundation
import CerebralTools

/// Enumerates installed applications from the standard application directories
/// (`/Applications`, `~/Applications`, `/System/Applications`) — never launches,
/// moves, or modifies anything. Icons come from `NSWorkspace.icon(forFile:)`,
/// rendered to a small PNG and size-capped so a pathological icon can never
/// bloat the tool output past its contract (`iconPng` maxLength).
///
/// The scan descends a bounded number of levels (NIC-175): plenty of real apps do not sit at the
/// top level of a search root — `/System/Applications/Utilities` holds Terminal, Disk Utility, and
/// Activity Monitor, and installers routinely create a vendor folder under `/Applications`. A
/// top-level-only scan made every one of those permanently undiscoverable, so they could be neither
/// opened by id nor pinned.
public struct MacAppDiscoveryCapability: AppDiscoveryCapability {
    /// Icon raster size: crisp on Retina tiles without heavy payloads.
    private static let iconPixelSize = 64
    /// Per-icon base64 cap, safely inside the contract's 131072 maxLength.
    private static let iconBase64Cap = 98304
    /// List cap — honest `truncated: true` beyond this, never a silent cut.
    private static let maxApps = 500
    /// How many directory levels below a search root to descend (NIC-175). Two covers the shapes
    /// that occur in practice — `Utilities/Terminal.app` at one, `Vendor/Suite/App.app` at two —
    /// without turning a picker open into a deep filesystem walk. Discovery runs on every picker
    /// open, so this bound is a responsiveness guarantee, not just a safety net.
    private static let maxSearchDepth = 2

    private let searchDirectories: [URL]

    public init(searchDirectories: [URL]? = nil) {
        self.searchDirectories = searchDirectories ?? [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
        ]
    }

    public func listApplications(includeIcons: Bool) async throws -> AppDiscoveryResult {
        Self.enumerate(searchDirectories: searchDirectories, includeIcons: includeIcons)
    }

    /// The synchronous enumeration core — also called directly by the shell at
    /// startup (icons off) to auto-mint app references before the runtime
    /// composes, so every installed app is openable by id from first launch.
    public static func enumerate(
        searchDirectories: [URL]? = nil, includeIcons: Bool
    ) -> AppDiscoveryResult {
        let searchDirectories = searchDirectories ?? MacAppDiscoveryCapability().searchDirectories
        let fileManager = FileManager.default
        var seen = Set<String>()
        var apps: [InstalledApplication] = []

        for directory in searchDirectories {
            for entry in Self.appBundles(in: directory, depth: 0, fileManager: fileManager) {
                guard
                    let bundle = Bundle(url: entry),
                    let bundleID = bundle.bundleIdentifier,
                    !seen.contains(bundleID)
                else { continue }
                seen.insert(bundleID)
                apps.append(InstalledApplication(
                    bundleID: bundleID,
                    name: fileManager.displayName(atPath: entry.path)
                        .replacingOccurrences(of: ".app", with: ""),
                    iconPNGBase64: includeIcons ? Self.iconBase64(for: entry) : nil
                ))
            }
        }

        apps.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let truncated = apps.count > Self.maxApps
        if truncated {
            apps = Array(apps.prefix(Self.maxApps))
        }
        return AppDiscoveryResult(apps: apps, truncated: truncated)
    }

    /// Every `.app` bundle at or below `directory`, to ``maxSearchDepth`` levels (NIC-175).
    ///
    /// An `.app` is itself a directory, so the one rule that matters is **never descend into one**:
    /// a bundle's `Contents` routinely holds helper and updater apps (Google Chrome ships
    /// `Google Chrome Helper.app`, Xcode ships dozens) which are implementation details, not things
    /// a user launches. Listing them would bury the real apps and mint junk references for them.
    ///
    /// An unreadable directory contributes nothing rather than aborting the scan — one permission
    /// error must not cost the user every other app on the machine.
    private static func appBundles(in directory: URL, depth: Int, fileManager: FileManager) -> [URL] {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        ) else { return [] }

        var found: [URL] = []
        for entry in entries {
            if entry.pathExtension == "app" {
                found.append(entry)
                continue
            }
            guard depth < maxSearchDepth,
                  (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            else { continue }
            found.append(contentsOf: appBundles(in: entry, depth: depth + 1, fileManager: fileManager))
        }
        return found
    }

    /// The application's icon as base64 PNG at ``iconPixelSize``; nil when the
    /// icon cannot be rendered or would exceed the size cap (honest fallback).
    private static func iconBase64(for appURL: URL) -> String? {
        let icon = NSWorkspace.shared.icon(forFile: appURL.path)
        let size = NSSize(width: iconPixelSize, height: iconPixelSize)
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: iconPixelSize, pixelsHigh: iconPixelSize,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        bitmap.size = size

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        NSGraphicsContext.current = context
        icon.draw(in: NSRect(origin: .zero, size: size))
        context.flushGraphics()

        guard let png = bitmap.representation(using: .png, properties: [:]) else { return nil }
        let base64 = png.base64EncodedString()
        return base64.count <= iconBase64Cap ? base64 : nil
    }
}
#endif
