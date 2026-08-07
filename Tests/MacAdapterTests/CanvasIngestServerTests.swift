// NIC-132 Increment 4b: the local Canvas ingest endpoint — the pure request parsing/auth helpers
// and the routing (POST-only, path-bound, bearer-authenticated, size-bounded, persist-on-success),
// plus the loopback listener over a real socket.
#if canImport(AppKit)
import Foundation
import Testing

import CerebralCore
import CerebralTools
@testable import CerebralMacAdapters

// MARK: - Test doubles

private final class InMemoryCanvasSnapshotStore: CanvasSnapshotStore, @unchecked Sendable {
    private let lock = NSLock()
    private var snapshot: CanvasScrapeSnapshot?
    private var count = 0

    func load() throws -> CanvasScrapeSnapshot? { lock.lock(); defer { lock.unlock() }; return snapshot }
    func save(_ snapshot: CanvasScrapeSnapshot) throws {
        lock.lock(); defer { lock.unlock() }; self.snapshot = snapshot; count += 1
    }
    func clear() throws { lock.lock(); defer { lock.unlock() }; snapshot = nil }

    var stored: CanvasScrapeSnapshot? { lock.lock(); defer { lock.unlock() }; return snapshot }
    var saves: Int { lock.lock(); defer { lock.unlock() }; return count }
}

private final class InMemorySecretStore: SecretStoreManaging, @unchecked Sendable {
    struct NotFound: Error {}
    private let lock = NSLock()
    private var values: [String: String] = [:]

    func store(reference: String, value: String) async throws {
        lock.withLock { values[reference] = value }
    }
    func readValue(reference: String) async throws -> String {
        try lock.withLock {
            guard let value = values[reference] else { throw NotFound() }
            return value
        }
    }
    func delete(reference: String) async throws {
        try lock.withLock {
            guard values.removeValue(forKey: reference) != nil else { throw NotFound() }
        }
    }
    var count: Int { lock.withLock { values.count } }
}

private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func raise() { lock.lock(); defer { lock.unlock() }; value = true }
    var isRaised: Bool { lock.lock(); defer { lock.unlock() }; return value }
}

private let validBody = """
{"schemaVersion":1,"scrapedAt":"2023-11-14T22:13:20Z","sourceUrl":"https://umamherst.instructure.com/","courses":[{"id":"1","name":"Course"}],"deadlines":[]}
"""

private func request(
    method: String = "POST",
    path: String = "/canvas/ingest",
    token: String? = "secret-token",
    body: String = validBody
) -> CanvasIngestRequest {
    var headers: [String: String] = [:]
    if let token { headers["authorization"] = "Bearer \(token)" }
    return CanvasIngestRequest(method: method, path: path, headers: headers, body: Data(body.utf8))
}

private func makeServer(
    store: any CanvasSnapshotStore,
    token: @escaping @Sendable () async -> String? = { "secret-token" },
    onIngest: (@Sendable () -> Void)? = nil
) -> CanvasIngestServer {
    CanvasIngestServer(port: 0, store: store, token: token, onIngest: onIngest)
}

// MARK: - Request parsing

@Test("a complete POST with a Content-Length body parses into method, path, headers, and body")
func canvasIngestServerParsesCompleteRequest() {
    let body = "hello"
    let raw = "POST /canvas/ingest?x=1 HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"
    guard case let .complete(parsed) = CanvasIngestServer.parseRequest(Data(raw.utf8), maxHeaderBytes: 16_384, maxBodyBytes: 512_000) else {
        Issue.record("expected a complete parse"); return
    }
    #expect(parsed.method == "POST")
    #expect(parsed.path == "/canvas/ingest") // query stripped
    #expect(parsed.headers["content-length"] == "5")
    #expect(String(decoding: parsed.body, as: UTF8.self) == "hello")
}

@Test("headers without the terminating blank line are incomplete, not invalid")
func canvasIngestServerIncompleteHeaders() {
    let raw = "POST /canvas/ingest HTTP/1.1\r\nHost: 127.0.0.1\r\n"
    #expect(CanvasIngestServer.parseRequest(Data(raw.utf8), maxHeaderBytes: 16_384, maxBodyBytes: 512_000) == .incomplete)
}

@Test("a body shorter than Content-Length is incomplete until the rest arrives")
func canvasIngestServerIncompleteBody() {
    let raw = "POST /canvas/ingest HTTP/1.1\r\nContent-Length: 10\r\n\r\nshort"
    #expect(CanvasIngestServer.parseRequest(Data(raw.utf8), maxHeaderBytes: 16_384, maxBodyBytes: 512_000) == .incomplete)
}

@Test("a Content-Length beyond the cap is rejected as too large")
func canvasIngestServerTooLarge() {
    let raw = "POST /canvas/ingest HTTP/1.1\r\nContent-Length: 999999\r\n\r\n"
    #expect(CanvasIngestServer.parseRequest(Data(raw.utf8), maxHeaderBytes: 16_384, maxBodyBytes: 1_024) == .tooLarge)
}

@Test("a malformed request line is invalid")
func canvasIngestServerInvalidRequestLine() {
    let raw = "GARBAGE\r\n\r\n"
    #expect(CanvasIngestServer.parseRequest(Data(raw.utf8), maxHeaderBytes: 16_384, maxBodyBytes: 512_000) == .invalid)
}

// MARK: - Bearer + constant-time compare

@Test("the bearer token is extracted case-insensitively; absent/malformed yields nil")
func canvasIngestServerBearerToken() {
    #expect(CanvasIngestServer.bearerToken(from: ["authorization": "Bearer abc123"]) == "abc123")
    #expect(CanvasIngestServer.bearerToken(from: ["authorization": "bearer abc123"]) == "abc123")
    #expect(CanvasIngestServer.bearerToken(from: [:]) == nil)
    #expect(CanvasIngestServer.bearerToken(from: ["authorization": "abc123"]) == nil) // no scheme
}

@Test("the constant-time compare matches equal tokens and rejects different ones")
func canvasIngestServerConstantTimeEquals() {
    #expect(CanvasIngestServer.constantTimeEquals(Array("token".utf8), Array("token".utf8)))
    #expect(!CanvasIngestServer.constantTimeEquals(Array("token".utf8), Array("tokeN".utf8)))
    #expect(!CanvasIngestServer.constantTimeEquals(Array("token".utf8), Array("tok".utf8)))
}

// MARK: - Routing

@Test("a POST with the correct token persists the scrape and answers 200")
func canvasIngestServerAcceptsValid() async {
    let store = InMemoryCanvasSnapshotStore()
    let ingested = Flag()
    let server = makeServer(store: store, onIngest: { ingested.raise() })
    let response = await server.respond(to: request())
    #expect(response.status == 200)
    #expect(store.saves == 1)
    #expect(store.stored?.courses.first?.name == "Course")
    #expect(ingested.isRaised)
}

@Test("a wrong token is 401 and never touches the store")
func canvasIngestServerRejectsWrongToken() async {
    let store = InMemoryCanvasSnapshotStore()
    let server = makeServer(store: store)
    let response = await server.respond(to: request(token: "not-it"))
    #expect(response.status == 401)
    #expect(store.saves == 0)
}

@Test("when no token has been minted, every request is 401")
func canvasIngestServerRejectsWhenNoTokenMinted() async {
    let store = InMemoryCanvasSnapshotStore()
    let server = makeServer(store: store, token: { nil })
    let response = await server.respond(to: request())
    #expect(response.status == 401)
    #expect(store.saves == 0)
}

@Test("a non-POST method is 405")
func canvasIngestServerRejectsNonPost() async {
    let store = InMemoryCanvasSnapshotStore()
    let response = await makeServer(store: store).respond(to: request(method: "GET"))
    #expect(response.status == 405)
    #expect(store.saves == 0)
}

@Test("a wrong path is 404")
func canvasIngestServerRejectsWrongPath() async {
    let store = InMemoryCanvasSnapshotStore()
    let response = await makeServer(store: store).respond(to: request(path: "/nope"))
    #expect(response.status == 404)
    #expect(store.saves == 0)
}

@Test("a malformed body from an authenticated caller is 400 and is not persisted")
func canvasIngestServerRejectsMalformedBody() async {
    let store = InMemoryCanvasSnapshotStore()
    let response = await makeServer(store: store).respond(to: request(body: "{not json"))
    #expect(response.status == 400)
    #expect(store.saves == 0)
}

// MARK: - Token minting

@Test("ensure() mints and stores a token when none exists, then returns the same one")
func canvasIngestTokenEnsureMintsOnce() async throws {
    let secrets = InMemorySecretStore()
    let first = try await CanvasIngestToken.ensure(in: secrets, generate: { "minted-token" })
    #expect(first == "minted-token")
    #expect(secrets.count == 1)
    // A second ensure returns the stored token, not a fresh mint.
    let second = try await CanvasIngestToken.ensure(in: secrets, generate: { "different" })
    #expect(second == "minted-token")
}

@Test("rotate() replaces the token and clear() removes it")
func canvasIngestTokenRotateAndClear() async throws {
    let secrets = InMemorySecretStore()
    _ = try await CanvasIngestToken.ensure(in: secrets, generate: { "one" })
    let rotated = try await CanvasIngestToken.rotate(in: secrets, generate: { "two" })
    #expect(rotated == "two")
    #expect(await CanvasIngestToken.load(from: secrets) == "two")
    await CanvasIngestToken.clear(from: secrets)
    #expect(await CanvasIngestToken.load(from: secrets) == nil)
}

@Test("a minted token is high-entropy and URL-safe")
func canvasIngestTokenRandomIsUrlSafe() {
    let token = CanvasIngestToken.randomToken()
    #expect(token.count >= 40)
    #expect(!token.contains("+") && !token.contains("/") && !token.contains("="))
}

// MARK: - Loopback listener over a real socket

@Test("the listener accepts an authenticated POST over the loopback socket and persists it")
func canvasIngestServerLoopbackAccepts() async throws {
    let store = InMemoryCanvasSnapshotStore()
    let server = CanvasIngestServer(port: 0, store: store, token: { "secret-token" })
    let port = try await server.start()
    defer { server.stop() }
    #expect(port != 0)

    var post = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/canvas/ingest")!)
    post.httpMethod = "POST"
    post.setValue("Bearer secret-token", forHTTPHeaderField: "Authorization")
    post.httpBody = Data(validBody.utf8)
    let (_, response) = try await URLSession.shared.data(for: post)
    #expect((response as? HTTPURLResponse)?.statusCode == 200)
    #expect(store.stored?.courses.first?.name == "Course")
}

@Test("the listener rejects a wrong token over the loopback socket with 401")
func canvasIngestServerLoopbackRejects() async throws {
    let store = InMemoryCanvasSnapshotStore()
    let server = CanvasIngestServer(port: 0, store: store, token: { "secret-token" })
    let port = try await server.start()
    defer { server.stop() }

    var post = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/canvas/ingest")!)
    post.httpMethod = "POST"
    post.setValue("Bearer wrong", forHTTPHeaderField: "Authorization")
    post.httpBody = Data(validBody.utf8)
    let (_, response) = try await URLSession.shared.data(for: post)
    #expect((response as? HTTPURLResponse)?.statusCode == 401)
    #expect(store.saves == 0)
}
#endif
