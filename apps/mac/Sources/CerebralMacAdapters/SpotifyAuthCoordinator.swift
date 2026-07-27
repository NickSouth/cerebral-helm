// Spotify OAuth connect: PKCE + a loopback listener + the system browser (NIC-133).
#if canImport(AppKit)
import Foundation
import Network
import CerebralCore
import CerebralTools

/// The result of a successful connect — the granted scope and the access-token expiry. The tokens
/// themselves are persisted to the Keychain, not returned (they never cross back to the UI).
public struct SpotifyConnection: Sendable, Equatable {
    public let scope: String?
    public let expiresAt: Date
}

/// A one-shot loopback HTTP server (NIC-133): binds `127.0.0.1:<port>`, opens the browser once it is
/// listening, and resolves with the query params of the first callback request. This is the
/// side-effectful seam — like the AppleScript scripting seams, the real socket is exercised by a
/// loopback integration test and the manual OAuth smoke; the request parsing and response building
/// are pure static helpers on ``SpotifyAuthCoordinator``. All state is confined to one serial queue,
/// so `@unchecked Sendable` is sound.
final class SpotifyLoopbackListener: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "com.cerebralhelm.spotify.loopback")
    private var continuation: CheckedContinuation<[String: String], Error>?
    private var buffer = Data()
    private var done = false

    init(port: UInt16) throws {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw SpotifyPlaybackError.providerFailed("Invalid loopback port \(port).")
        }
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        // Bind loopback only — the callback is local; nothing off-machine can reach it.
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: nwPort)
        self.listener = try NWListener(using: parameters)
    }

    /// Starts listening, calls `onListening` once ready (open the browser there), and resolves with
    /// the first callback's query params. Fails on listener error or after `timeout`.
    func awaitCallback(
        timeout: TimeInterval, onListening: @escaping @Sendable () -> Void
    ) async throws -> [String: String] {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[String: String], Error>) in
            queue.async { self.continuation = continuation }
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    onListening()
                case let .failed(error):
                    self?.finish(.failure(SpotifyPlaybackError.providerFailed(
                        "The loopback listener failed: \(error.localizedDescription)")))
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            listener.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) { [weak self] in
                self?.finish(.failure(SpotifyPlaybackError.providerFailed(
                    "Timed out waiting for the Spotify authorization callback.")))
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
                let query = SpotifyAuthCoordinator.query(fromRequestLine: line)
                self.respond(on: connection)
                self.finish(.success(query))
                return
            }
            if isComplete || error != nil {
                self.finish(.failure(SpotifyPlaybackError.providerFailed(
                    "The authorization callback closed before a request was received.")))
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

    private func respond(on connection: NWConnection) {
        let response = SpotifyAuthCoordinator.httpResponse(html: SpotifyAuthCoordinator.successHTML)
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

/// Runs the Spotify Authorization Code + PKCE connect flow on this Mac (NIC-133): generate PKCE,
/// bind a loopback listener, open the system browser to Spotify's consent page, capture the
/// redirected `?code`, exchange it for tokens, and persist them to the Keychain. The redirect URI is
/// a fixed loopback address (`http://127.0.0.1:<port>/callback`) — the user registers exactly this in
/// their Spotify app's allowlist (Spotify permits loopback HTTP). Request parsing / response building
/// / the CSRF-state check are pure static helpers (unit-tested); the full round trip is
/// browser-interactive, so it is verified by the manual OAuth smoke once the connect trigger exists
/// (Increment 6).
public struct SpotifyAuthCoordinator: Sendable {
    private let exchange: SpotifyTokenExchange
    private let secretStore: any SecretStoreManaging
    private let workspace: any WorkspaceOpening
    private let port: UInt16
    private let callbackPath: String
    private let timeout: TimeInterval

    public init(
        exchange: SpotifyTokenExchange = SpotifyTokenExchange(),
        secretStore: any SecretStoreManaging,
        workspace: any WorkspaceOpening = SystemWorkspace(),
        port: UInt16 = 8888,
        callbackPath: String = "/callback",
        timeout: TimeInterval = 180
    ) {
        self.exchange = exchange
        self.secretStore = secretStore
        self.workspace = workspace
        self.port = port
        self.callbackPath = callbackPath
        self.timeout = timeout
    }

    /// The loopback redirect URI the user must register in their Spotify app's allowlist.
    public var redirectURI: String { "http://127.0.0.1:\(port)\(callbackPath)" }

    public func connect(clientID: String, now: Date = Date()) async throws -> SpotifyConnection {
        let verifier = SpotifyPKCE.makeVerifier()
        let challenge = SpotifyPKCE.challenge(for: verifier)
        let state = SpotifyPKCE.makeState()
        guard let authorizeURL = exchange.authorizeURL(
            clientID: clientID, redirectURI: redirectURI, challenge: challenge, state: state
        ) else {
            throw SpotifyPlaybackError.providerFailed("Could not build the Spotify authorize URL.")
        }

        let listener = try SpotifyLoopbackListener(port: port)
        let workspace = self.workspace
        let query = try await listener.awaitCallback(timeout: timeout) {
            // Open the browser only once the listener is accepting, so the redirect can't race the bind.
            Task { try? await workspace.openURL(authorizeURL) }
        }

        let code = try Self.authorizationCode(fromQuery: query, expectedState: state).get()
        let tokens = try await exchange.exchange(
            code: code, verifier: verifier, redirectURI: redirectURI, clientID: clientID, now: now
        )
        try await SpotifyTokenBlob.save(tokens, to: secretStore)
        return SpotifyConnection(scope: tokens.scope, expiresAt: tokens.expiresAt)
    }

    /// Removes the stored authorization (the "disconnect" path, Increment 6). Missing tokens are not
    /// an error — disconnecting an already-disconnected account is a no-op success.
    public func disconnect() async throws {
        do {
            try await secretStore.delete(reference: SpotifyTokenBlob.reference)
        } catch {
            // Already absent — nothing to remove.
        }
    }

    // MARK: - Pure helpers (unit-tested)

    /// The query params of an HTTP request line like `GET /callback?code=abc&state=xyz HTTP/1.1`.
    static func query(fromRequestLine line: String) -> [String: String] {
        let parts = line.split(separator: " ")
        guard parts.count >= 2, let components = URLComponents(string: String(parts[1])) else { return [:] }
        var query: [String: String] = [:]
        for item in components.queryItems ?? [] { query[item.name] = item.value ?? "" }
        return query
    }

    /// Validates the callback and extracts the authorization code. An `error` param (e.g. the user
    /// declined) fails; a mismatched `state` fails the CSRF check; a missing code fails. The failure
    /// diagnostic is coarse and never surfaced verbatim (the widget shows a generic message).
    static func authorizationCode(
        fromQuery query: [String: String], expectedState: String
    ) -> Result<String, SpotifyPlaybackError> {
        if let error = query["error"] {
            return .failure(.providerFailed("Spotify authorization was not granted (\(error))."))
        }
        guard query["state"] == expectedState else {
            return .failure(.providerFailed("The authorization response failed the CSRF state check."))
        }
        guard let code = query["code"], !code.isEmpty else {
            return .failure(.providerFailed("The authorization response contained no code."))
        }
        return .success(code)
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

    /// The page the browser shows after the redirect is captured.
    static let successHTML = """
    <!doctype html><html><head><meta charset="utf-8"><title>CerebralHelm</title></head>\
    <body style="font-family:-apple-system,system-ui,sans-serif;text-align:center;padding-top:4rem;color:#111">\
    <h2>Spotify connected</h2><p>You can close this tab and return to CerebralHelm.</p></body></html>
    """
}
#endif
