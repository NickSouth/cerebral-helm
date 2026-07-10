// NIC-147 Increment 2: the macOS favicon adapter — real fetch + AppKit decode.
// Gated so the Linux CI package build compiles this target empty; a stub fetcher
// serves canned HTML and image bytes so no network is touched.
#if canImport(AppKit)
import AppKit
import Foundation
import Testing

import CerebralTools
@testable import CerebralMacAdapters

private struct MapFetcher: HTTPResourceFetcher {
    var responses: [String: FetchedResource] = [:]
    func get(_ url: URL) async -> FetchedResource? { responses[url.absoluteString] }
}

private func htmlResource(_ body: String) -> FetchedResource {
    FetchedResource(data: Data(body.utf8), mimeType: "text/html")
}

/// A real, small PNG rendered offscreen — the input the normalizer must accept.
private func solidPNG(width: Int = 16, height: Int = 16) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.systemBlue.setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

private let pngMagic: [UInt8] = [0x89, 0x50, 0x4E, 0x47]

@Test("fetches the declared apple-touch-icon and normalizes it to a capped PNG")
func fetchesAndNormalizesDeclaredIcon() async {
    let iconBytes = solidPNG()
    let fetcher = MapFetcher(responses: [
        "https://acme.test/": htmlResource("""
        <link rel="apple-touch-icon" href="/touch.png" sizes="180x180">
        """),
        "https://acme.test/touch.png": FetchedResource(data: iconBytes, mimeType: "image/png"),
    ])
    let png = await MacFaviconCapability(fetcher: fetcher)
        .fetchFavicon(for: URL(string: "https://acme.test/dashboard")!)

    let bytes = try? #require(png)
    #expect(Array((bytes ?? Data()).prefix(4)) == pngMagic)
    #expect((bytes?.count ?? .max) <= MacFaviconCapability.pngByteCap)
}

@Test("falls back through candidates to the well-known favicon.ico")
func fallsBackToWellKnown() async {
    // No declared links; only /favicon.ico serves an image.
    let fetcher = MapFetcher(responses: [
        "https://acme.test/": htmlResource("<html><head></head></html>"),
        "https://acme.test/favicon.ico": FetchedResource(data: solidPNG(), mimeType: "image/x-icon"),
    ])
    let png = await MacFaviconCapability(fetcher: fetcher)
        .fetchFavicon(for: URL(string: "https://acme.test/")!)
    #expect(png != nil)
}

@Test("returns nil when no candidate yields a decodable image")
func nilWhenNothingDecodes() async {
    let fetcher = MapFetcher(responses: [
        "https://acme.test/": htmlResource("<link rel=\"icon\" href=\"/bad.png\">"),
        // A non-image body (an HTML error page dressed as an icon) must be rejected.
        "https://acme.test/bad.png": FetchedResource(data: Data("not an image".utf8), mimeType: "image/png"),
    ])
    let png = await MacFaviconCapability(fetcher: fetcher)
        .fetchFavicon(for: URL(string: "https://acme.test/")!)
    #expect(png == nil)
}

@Test("returns nil for a non-web target without any fetch")
func nilForNonWebTarget() async {
    let png = await MacFaviconCapability(fetcher: MapFetcher())
        .fetchFavicon(for: URL(string: "file:///etc/hosts")!)
    #expect(png == nil)
}

@Test("normalize accepts a real image and rejects empty or garbage bytes")
func normalizeAcceptsImagesRejectsGarbage() {
    let normalized = MacFaviconCapability.normalize(solidPNG(width: 200, height: 200))
    #expect(normalized != nil)
    #expect(Array((normalized ?? Data()).prefix(4)) == pngMagic)
    #expect(MacFaviconCapability.normalize(Data()) == nil)
    #expect(MacFaviconCapability.normalize(Data("<html>404</html>".utf8)) == nil)
}
#endif
