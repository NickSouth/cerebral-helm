import Foundation
import WebKit
import os

/// Serves the bundled offline dashboard build to a `WKWebView` over the private
/// `cerebral://app/` origin (NIC-73 / FR-SHL-03).
///
/// No network or dev server is involved: every request is resolved to a file under
/// the app bundle's dashboard resources. A request for a missing file completes with
/// a 404 and is logged and recorded as a diagnostic, so an incomplete or broken
/// bundle is visible rather than a silent blank page (FR-SHL-03 AC). Path traversal
/// outside the bundle root is refused.
final class CerebralSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "cerebral"
    static let host = "app"
    static var indexURL: URL { URL(string: "\(scheme)://\(host)/index.html")! }

    private let root: URL
    private let log = Logger(subsystem: "local.cerebralhelm.CerebralHelm", category: "dashboard")

    /// Missing asset paths observed this session, newest last (diagnostics surface).
    private(set) var missingAssets: [String] = []

    init(root: URL) {
        self.root = root.standardizedFileURL
        super.init()
    }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else {
            task.didFailWithError(URLError(.badURL))
            return
        }

        // Map the URL path to a file under the dashboard root; "/" → index.html.
        var relative = url.path
        if relative.isEmpty || relative == "/" { relative = "/index.html" }

        let fileURL = root.appendingPathComponent(relative).standardizedFileURL

        // Refuse anything that escapes the bundle root (e.g. "/../secrets").
        guard fileURL.path == root.path || fileURL.path.hasPrefix(root.path + "/") else {
            respondNotFound(task, url: url, path: relative)
            return
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory),
              !isDirectory.boolValue,
              let data = try? Data(contentsOf: fileURL) else {
            respondNotFound(task, url: url, path: relative)
            return
        }

        let headers = [
            "Content-Type": Self.mimeType(forExtension: fileURL.pathExtension),
            "Content-Length": String(data.count),
            "Cache-Control": "no-store"
        ]
        let response = HTTPURLResponse(
            url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers
        )!
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {
        // Requests are served synchronously in `start`; there is nothing to cancel.
    }

    private func respondNotFound(_ task: WKURLSchemeTask, url: URL, path: String) {
        missingAssets.append(path)
        log.error("Dashboard asset missing: \(path, privacy: .public)")
        let response = HTTPURLResponse(
            url: url, statusCode: 404, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/plain; charset=utf-8"]
        )!
        task.didReceive(response)
        task.didReceive(Data("Not found: \(path)".utf8))
        task.didFinish()
    }

    static func mimeType(forExtension ext: String) -> String {
        switch ext.lowercased() {
        case "html", "htm": return "text/html; charset=utf-8"
        case "js", "mjs": return "text/javascript; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "json", "map": return "application/json; charset=utf-8"
        case "svg": return "image/svg+xml"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "webp": return "image/webp"
        case "gif": return "image/gif"
        case "woff2": return "font/woff2"
        case "woff": return "font/woff"
        case "ttf": return "font/ttf"
        case "ico": return "image/x-icon"
        default: return "application/octet-stream"
        }
    }
}
