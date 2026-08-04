// A one-shot loopback HTTP listener for OAuth redirect capture, shared by every provider.
#if canImport(AppKit)
import Foundation
import Network

/// Why a loopback callback never arrived. Provider-neutral: each coordinator maps these onto its
/// own error type, so Spotify's and Google's surfaces keep saying what their users need to hear.
public enum LoopbackAuthError: Error, Equatable, Sendable {
    case bindFailed(String)
    case timedOut(String)
    /// The browser connected and closed without sending a request line.
    case closedEarly
}

/// A one-shot loopback HTTP server: binds `127.0.0.1:<port>`, tells the caller once it is actually
/// listening, and resolves with the query parameters of the first request it receives.
///
/// Extracted from the Spotify implementation when Gmail became the second OAuth provider
/// (2026-08-04). This is socket machinery — accept a connection, read a request line, write a
/// response — with nothing provider-specific in it, and two copies would have to be kept correct in
/// parallel forever. (Contrast `google.search` / `youtube.search`, where the duplication *is* the
/// safety property; nothing here chooses a destination.)
///
/// This is the side-effectful seam: the real socket is exercised by a loopback integration test and
/// by the manual OAuth smoke, while request parsing and response building are pure static helpers
/// on the coordinators. All state is confined to one serial queue, so `@unchecked Sendable` is
/// sound.
final class LoopbackAuthListener: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "com.cerebralhelm.oauth.loopback")
    private var continuation: CheckedContinuation<[String: String], Error>?
    private var buffer = Data()
    private var done = false
    private let responseHTML: String

    /// `port` 0 asks the kernel for a free ephemeral port — the bound port is reported to
    /// `awaitCallback`'s `onListening`. Production flows pass their fixed registered port; tests
    /// bind 0 so they can never collide with whatever else holds a given port.
    init(port: UInt16, responseHTML: String) throws {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw LoopbackAuthError.bindFailed("Invalid loopback port \(port).")
        }
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        // Bind loopback only — the callback is local, and nothing off-machine can reach it.
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: nwPort)
        self.listener = try NWListener(using: parameters)
        self.responseHTML = responseHTML
    }

    /// Starts listening, calls `onListening` with the bound port once ready (open the browser
    /// there, never before — otherwise the redirect can race the bind), and resolves with the first
    /// callback's query parameters.
    func awaitCallback(
        timeout: TimeInterval, onListening: @escaping @Sendable (UInt16) -> Void
    ) async throws -> [String: String] {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[String: String], Error>) in
            queue.async { self.continuation = continuation }
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    onListening(self?.listener.port?.rawValue ?? 0)
                case let .failed(error):
                    self?.finish(.failure(LoopbackAuthError.bindFailed(error.localizedDescription)))
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            listener.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) { [weak self] in
                self?.finish(.failure(LoopbackAuthError.timedOut(
                    "Timed out waiting for the authorization callback.")))
            }
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection)
    }

    private func receive(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data { self.buffer.append(data) }
            if let line = Self.requestLine(from: self.buffer) {
                let query = Self.query(fromRequestLine: line)
                self.respond(on: connection)
                self.finish(.success(query))
                return
            }
            if isComplete || error != nil {
                self.finish(.failure(LoopbackAuthError.closedEarly))
                return
            }
            self.receive(on: connection)
        }
    }

    /// The first CRLF-terminated line of an accumulated HTTP request, or nil until it arrives.
    private static func requestLine(from buffer: Data) -> String? {
        guard let range = buffer.range(of: Data("\r\n".utf8)) else { return nil }
        return String(decoding: buffer[..<range.lowerBound], as: UTF8.self)
    }

    /// The query params of a request line like `GET /callback?code=abc&state=xyz HTTP/1.1`.
    static func query(fromRequestLine line: String) -> [String: String] {
        let parts = line.split(separator: " ")
        guard parts.count >= 2, let components = URLComponents(string: String(parts[1])) else { return [:] }
        var query: [String: String] = [:]
        for item in components.queryItems ?? [] { query[item.name] = item.value ?? "" }
        return query
    }

    /// A minimal HTTP/1.1 response wrapping `html`, with an explicit length and a close.
    static func httpResponse(html: String) -> Data {
        let body = Data(html.utf8)
        let header = "HTTP/1.1 200 OK\r\n"
            + "Content-Type: text/html; charset=utf-8\r\n"
            + "Content-Length: \(body.count)\r\n"
            + "Connection: close\r\n\r\n"
        return Data(header.utf8) + body
    }

    /// The page the browser shows after a captured redirect.
    static func successHTML(title: String) -> String {
        """
        <!doctype html><html><head><meta charset="utf-8"><title>CerebralHelm</title></head>\
        <body style="font-family:-apple-system,system-ui,sans-serif;text-align:center;padding-top:4rem;color:#111">\
        <h2>\(title)</h2><p>You can close this tab and return to CerebralHelm.</p></body></html>
        """
    }

    private func respond(on connection: NWConnection) {
        let response = Self.httpResponse(html: responseHTML)
        connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
    }

    /// Resolves the continuation exactly once and tears the listener down.
    private func finish(_ result: Result<[String: String], Error>) {
        guard !done else { return }
        done = true
        let continuation = self.continuation
        self.continuation = nil
        listener.cancel()
        switch result {
        case let .success(query):
            continuation?.resume(returning: query)
        case let .failure(error):
            continuation?.resume(throwing: error)
        }
    }
}
#endif
