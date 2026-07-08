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
public struct MacAppDiscoveryCapability: AppDiscoveryCapability {
    /// Icon raster size: crisp on Retina tiles without heavy payloads.
    private static let iconPixelSize = 64
    /// Per-icon base64 cap, safely inside the contract's 131072 maxLength.
    private static let iconBase64Cap = 98304
    /// List cap — honest `truncated: true` beyond this, never a silent cut.
    private static let maxApps = 500

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
            guard let entries = try? fileManager.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
            ) else { continue }
            for entry in entries where entry.pathExtension == "app" {
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
