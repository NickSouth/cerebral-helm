// Site favicon fetch + normalization for URL quick apps (NIC-147, FR-TOL-04).
#if canImport(AppKit)
import AppKit
import Foundation
import CerebralTools

/// Fetches a URL's favicon and normalizes it to a small PNG the dashboard renders
/// exactly like an app icon. The candidate order (apple-touch-icon → declared
/// `<link>` icons → `/favicon.ico`) is resolved by the portable ``FaviconResolver``;
/// this adapter supplies the real network fetch and the AppKit image decode +
/// re-render, mirroring ``MacAppDiscoveryCapability``'s icon normalizer so URL and
/// app tiles carry identically shaped icons.
///
/// The fetch is a direct-to-site GET for a public asset on the host the user
/// already pinned — no third-party favicon service, no user data sent (NIC-147
/// owner decision). Any failure yields `nil`; the caller records the miss.
public struct MacFaviconCapability: FaviconCapability {
    /// Icon raster size: crisp on Retina tiles without heavy payloads (matches the
    /// app-icon adapter).
    static let iconPixelSize = 64
    /// PNG byte cap. base64 of this stays inside the contract's `iconPng` maxLength
    /// (131072); `98304 * 4/3 == 131072`, matching the app-icon cap.
    static let pngByteCap = 98304
    /// Bound the work: try at most this many candidates before giving up.
    static let maxCandidates = 6

    private let fetcher: any HTTPResourceFetcher

    public init(fetcher: any HTTPResourceFetcher = URLSessionResourceFetcher()) {
        self.fetcher = fetcher
    }

    public func fetchFavicon(for url: URL) async -> Data? {
        let candidates = await FaviconResolver(fetcher: fetcher).candidateURLs(for: url)
        for candidate in candidates.prefix(Self.maxCandidates) {
            guard let resource = await fetcher.get(candidate) else { continue }
            if let png = Self.normalize(resource.data) { return png }
        }
        return nil
    }

    /// Decodes arbitrary favicon bytes (`.ico`/`.png`/`.jpg`/…) via `NSImage` and
    /// re-renders to a fixed-size PNG, size-capped. Returns `nil` for undecodable
    /// bytes (an HTML error page, an empty body) or an over-cap result — an honest
    /// fallback, never an invented icon.
    static func normalize(_ data: Data) -> Data? {
        guard
            !data.isEmpty,
            let image = NSImage(data: data),
            image.size.width > 0, image.size.height > 0
        else { return nil }

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
        image.draw(in: NSRect(origin: .zero, size: size))
        context.flushGraphics()

        guard let png = bitmap.representation(using: .png, properties: [:]) else { return nil }
        return png.count <= pngByteCap ? png : nil
    }
}

/// The live `HTTPResourceFetcher`: a single bounded, ephemeral GET. Non-2xx,
/// empty, over-cap, or errored responses return `nil` so the resolver treats them
/// as an unavailable candidate. Ephemeral config keeps nothing on disk; a short
/// timeout means a slow host degrades to the placeholder rather than hanging a tile.
public struct URLSessionResourceFetcher: HTTPResourceFetcher {
    private let session: URLSession
    private let maxBytes: Int

    public init(maxBytes: Int = 512 * 1024, timeout: TimeInterval = 8) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        self.session = URLSession(configuration: configuration)
        self.maxBytes = maxBytes
    }

    public func get(_ url: URL) async -> FetchedResource? {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("CerebralHelm", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await session.data(for: request) else { return nil }
        if let http = response as? HTTPURLResponse, !(200 ... 299).contains(http.statusCode) { return nil }
        guard !data.isEmpty, data.count <= maxBytes else { return nil }
        return FetchedResource(data: data, mimeType: response.mimeType?.lowercased())
    }
}
#endif
