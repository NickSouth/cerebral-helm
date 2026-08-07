// The local Canvas ingest endpoint (NIC-132): a persistent loopback HTTP server the Chrome
// extension POSTs scraped courses/deadlines to. This is the one inbound attack surface in the app,
// so it is authenticated (a minted bearer token, constant-time checked), loopback-only, method- and
// path- and size-bounded, and it only ever persists validated data — it never executes anything.
#if canImport(AppKit)
import Foundation
import Network
import CerebralCore
import CerebralTools

/// The minted bearer token that authenticates the Chrome extension to the local ingest endpoint
/// (NIC-132). Stored as a single Keychain value under `canvas_ingest_token`; the settings surface
/// (Increment 6) shows it once for the user to paste into the extension, and disconnect rotates it.
/// This is a live secret — never log it.
public enum CanvasIngestToken {
    public static let reference = "canvas_ingest_token"

    /// The current token, or `nil` when none has been minted (or the store can't be read).
    public static func load(from store: any SecretStoreManaging) async -> String? {
        try? await store.readValue(reference: reference)
    }

    /// The current token, minting and storing a fresh one when none exists.
    public static func ensure(
        in store: any SecretStoreManaging, generate: () -> String = randomToken
    ) async throws -> String {
        if let existing = try? await store.readValue(reference: reference), !existing.isEmpty {
            return existing
        }
        let token = generate()
        try await store.store(reference: reference, value: token)
        return token
    }

    /// Replaces the token with a fresh value (the disconnect path, Increment 6), returning the new one.
    public static func rotate(
        in store: any SecretStoreManaging, generate: () -> String = randomToken
    ) async throws -> String {
        let token = generate()
        try await store.store(reference: reference, value: token)
        return token
    }

    /// Removes the token. A missing token is not an error.
    public static func clear(from store: any SecretStoreManaging) async {
        try? await store.delete(reference: reference)
    }

    /// 32 cryptographically-random bytes as URL-safe base64 (~256 bits of entropy). `SystemRandom`
    /// is the platform CSPRNG on Apple platforms.
    public static func randomToken() -> String {
        var rng = SystemRandomNumberGenerator()
        let bytes = (0..<32).map { _ in UInt8.random(in: 0...255, using: &rng) }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// A parsed inbound HTTP request (only the parts the ingest endpoint needs).
struct CanvasIngestRequest: Equatable {
    let method: String
    /// The request path with any query string removed.
    let path: String
    /// Header names lowercased for case-insensitive lookup.
    let headers: [String: String]
    let body: Data
}

/// The outcome of parsing accumulated request bytes.
enum CanvasIngestParse: Equatable {
    case incomplete
    case tooLarge
    case invalid
    case complete(CanvasIngestRequest)
}

/// The response the endpoint will send: an HTTP status, its reason phrase, and a short plain body.
struct CanvasIngestResponse: Equatable {
    let status: Int
    let reason: String
    let body: String
}

/// A persistent loopback HTTP server for Canvas scrape ingestion (NIC-132).
///
/// Binds `127.0.0.1:<port>` and accepts `POST <path>` with an `Authorization: Bearer <token>`
/// header; a valid request is decoded through ``CanvasIngest`` and persisted via the injected store,
/// then `onIngest` fires (the widget refresh, Increment 5). Everything else is rejected with a status
/// code and no side effects: a non-POST is `405`, a wrong path `404`, a missing/incorrect token
/// `401`, an oversized body `413`, and a malformed body `400`. The request parsing, auth, and routing
/// are pure static/instance helpers (unit-tested); the socket itself is exercised by a loopback
/// integration test and a `curl` smoke.
///
/// All mutable state is confined to one serial queue, so `@unchecked Sendable` is sound.
public final class CanvasIngestServer: @unchecked Sendable {
    private let requestedPort: UInt16
    private let path: String
    private let maxHeaderBytes: Int
    private let maxBodyBytes: Int
    private let store: any CanvasSnapshotStore
    private let token: @Sendable () async -> String?
    private let onIngest: (@Sendable () -> Void)?

    private let queue = DispatchQueue(label: "com.cerebralhelm.canvas.ingest")
    private var listener: NWListener?
    private var startContinuation: CheckedContinuation<UInt16, Error>?
    private var startResolved = false

    /// - Parameters:
    ///   - port: the loopback port to bind; `0` lets the OS assign an ephemeral port (used by tests).
    ///   - token: reads the current expected bearer token (nil ⇒ nothing accepted). Read per request
    ///            so a rotated/cleared token takes effect immediately.
    ///   - onIngest: fired after a scrape is accepted and persisted (the widget refresh).
    public init(
        port: UInt16,
        path: String = "/canvas/ingest",
        maxHeaderBytes: Int = 16 * 1024,
        maxBodyBytes: Int = 512 * 1024,
        store: any CanvasSnapshotStore,
        token: @escaping @Sendable () async -> String?,
        onIngest: (@Sendable () -> Void)? = nil
    ) {
        self.requestedPort = port
        self.path = path
        self.maxHeaderBytes = maxHeaderBytes
        self.maxBodyBytes = maxBodyBytes
        self.store = store
        self.token = token
        self.onIngest = onIngest
    }

    /// Binds the listener and resolves with the actual bound port once it is ready.
    public func start() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                self.startContinuation = continuation
                do {
                    let listener = try self.makeListener()
                    self.listener = listener
                    listener.stateUpdateHandler = { [weak self] state in
                        switch state {
                        case .ready:
                            self?.resolveStart(.success(listener.port?.rawValue ?? self?.requestedPort ?? 0))
                        case let .failed(error):
                            self?.resolveStart(.failure(error))
                        default:
                            break
                        }
                    }
                    listener.newConnectionHandler = { [weak self] connection in
                        self?.accept(connection)
                    }
                    listener.start(queue: self.queue)
                } catch {
                    self.resolveStart(.failure(error))
                }
            }
        }
    }

    /// Stops accepting connections.
    public func stop() {
        queue.async {
            self.listener?.cancel()
            self.listener = nil
        }
    }

    private func makeListener() throws -> NWListener {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        let nwPort: NWEndpoint.Port = requestedPort == 0
            ? .any
            : (NWEndpoint.Port(rawValue: requestedPort) ?? .any)
        // Loopback only — nothing off-machine can reach the endpoint.
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: nwPort)
        return try NWListener(using: parameters)
    }

    private func resolveStart(_ result: Result<UInt16, Error>) {
        guard !startResolved else { return }
        startResolved = true
        let continuation = startContinuation
        startContinuation = nil
        switch result {
        case let .success(port): continuation?.resume(returning: port)
        case let .failure(error): continuation?.resume(throwing: error)
        }
    }

    // MARK: - Connection handling

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(connection, buffer: Data())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { connection.cancel(); return }
            var buffer = buffer
            if let data { buffer.append(data) }
            switch Self.parseRequest(buffer, maxHeaderBytes: self.maxHeaderBytes, maxBodyBytes: self.maxBodyBytes) {
            case .incomplete:
                if isComplete || error != nil {
                    self.reply(connection, Self.plain(400, "Bad Request", "incomplete request"))
                } else {
                    self.receive(connection, buffer: buffer)
                }
            case .tooLarge:
                self.reply(connection, Self.plain(413, "Payload Too Large", "payload too large"))
            case .invalid:
                self.reply(connection, Self.plain(400, "Bad Request", "invalid request"))
            case let .complete(request):
                Task { [weak self] in
                    guard let self else { connection.cancel(); return }
                    self.reply(connection, await self.respond(to: request))
                }
            }
        }
    }

    private func reply(_ connection: NWConnection, _ response: CanvasIngestResponse) {
        let data = Self.httpResponse(response)
        connection.send(content: data, completion: .contentProcessed { _ in connection.cancel() })
    }

    // MARK: - Routing (unit-tested)

    /// Routes a fully-parsed request to a response, persisting a valid scrape. Auth is checked before
    /// the body is ever decoded, so an unauthenticated caller's body is never processed. The store is
    /// touched only on the success path.
    func respond(to request: CanvasIngestRequest) async -> CanvasIngestResponse {
        guard request.method.uppercased() == "POST" else {
            return Self.plain(405, "Method Not Allowed", "POST only")
        }
        guard request.path == path else {
            return Self.plain(404, "Not Found", "not found")
        }
        let expected = await token()
        guard
            let expected, !expected.isEmpty,
            let provided = Self.bearerToken(from: request.headers),
            Self.constantTimeEquals(Array(provided.utf8), Array(expected.utf8))
        else {
            return Self.plain(401, "Unauthorized", "unauthorized")
        }
        do {
            let snapshot = try CanvasIngest.snapshot(fromBody: request.body)
            try store.save(snapshot)
            onIngest?()
            return Self.plain(200, "OK", "accepted")
        } catch {
            return Self.plain(400, "Bad Request", "invalid payload")
        }
    }

    // MARK: - Pure helpers (unit-tested)

    /// Parses accumulated request bytes: `.incomplete` until the headers and any `Content-Length`
    /// body have all arrived, `.tooLarge` when the body exceeds `maxBodyBytes` (or the headers
    /// exceed `maxHeaderBytes`), `.invalid` for a malformed request line, else `.complete`.
    static func parseRequest(
        _ data: Data, maxHeaderBytes: Int, maxBodyBytes: Int
    ) -> CanvasIngestParse {
        guard let separator = data.range(of: Data("\r\n\r\n".utf8)) else {
            return data.count > maxHeaderBytes ? .invalid : .incomplete
        }
        let head = data[data.startIndex..<separator.lowerBound]
        let bodyBytes = data[separator.upperBound...]

        let headLines = head.split(separator: UInt8(ascii: "\n"))
        guard let firstLine = headLines.first else { return .invalid }
        let requestLine = String(decoding: firstLine, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return .invalid }
        let method = String(parts[0])
        let target = String(parts[1])
        let path = String(target.split(separator: "?", maxSplits: 1).first ?? "")

        var headers: [String: String] = [:]
        for line in headLines.dropFirst() {
            let text = String(decoding: line, as: UTF8.self)
            guard let colon = text.firstIndex(of: ":") else { continue }
            let key = text[..<colon].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = text[text.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty { headers[key] = value }
        }

        if let lengthText = headers["content-length"], let length = Int(lengthText) {
            if length > maxBodyBytes { return .tooLarge }
            if bodyBytes.count < length { return .incomplete }
            let end = bodyBytes.index(bodyBytes.startIndex, offsetBy: length)
            return .complete(CanvasIngestRequest(
                method: method, path: path, headers: headers, body: Data(bodyBytes[bodyBytes.startIndex..<end])
            ))
        }

        // No Content-Length: take whatever body arrived, still bounded.
        if bodyBytes.count > maxBodyBytes { return .tooLarge }
        return .complete(CanvasIngestRequest(
            method: method, path: path, headers: headers, body: Data(bodyBytes)
        ))
    }

    /// The bearer token from an `Authorization: Bearer <token>` header, or nil when absent/malformed.
    static func bearerToken(from headers: [String: String]) -> String? {
        guard let authorization = headers["authorization"] else { return nil }
        let parts = authorization.split(separator: " ", maxSplits: 1)
        guard parts.count == 2, parts[0].lowercased() == "bearer" else { return nil }
        let token = parts[1].trimmingCharacters(in: .whitespaces)
        return token.isEmpty ? nil : token
    }

    /// Length-checked constant-time byte comparison — avoids leaking how much of the token matched
    /// via timing. (Length itself is not secret: the token is a fixed-size minted value.)
    static func constantTimeEquals(_ a: [UInt8], _ b: [UInt8]) -> Bool {
        guard a.count == b.count else { return false }
        var difference: UInt8 = 0
        for index in a.indices { difference |= a[index] ^ b[index] }
        return difference == 0
    }

    static func plain(_ status: Int, _ reason: String, _ body: String) -> CanvasIngestResponse {
        CanvasIngestResponse(status: status, reason: reason, body: body)
    }

    /// A minimal HTTP/1.1 response with an explicit length and a connection close.
    static func httpResponse(_ response: CanvasIngestResponse) -> Data {
        let body = Data(response.body.utf8)
        let header = "HTTP/1.1 \(response.status) \(response.reason)\r\n"
            + "Content-Type: text/plain; charset=utf-8\r\n"
            + "Content-Length: \(body.count)\r\n"
            + "Connection: close\r\n\r\n"
        return Data(header.utf8) + body
    }
}
#endif
