// NIC-133 Increment 4: the connect flow's pure helpers (callback parsing, CSRF-state check,
// HTTP response) and the loopback listener over a real socket. The full browser round trip is
// interactive and is verified by the manual OAuth smoke once the connect trigger exists (Inc 6).
#if canImport(AppKit)
import Foundation
import Testing

import CerebralCore
import CerebralTools
@testable import CerebralMacAdapters

@Test("the callback request line parses into its query params")
func spotifyCallbackQueryParsing() {
    let query = SpotifyAuthCoordinator.query(
        fromRequestLine: "GET /callback?code=abc123&state=xyz789 HTTP/1.1"
    )
    #expect(query["code"] == "abc123")
    #expect(query["state"] == "xyz789")
    // A line without a target yields no params rather than crashing.
    #expect(SpotifyAuthCoordinator.query(fromRequestLine: "GARBAGE").isEmpty)
}

@Test("a matching state with a code yields the authorization code")
func spotifyAuthCodeSuccess() throws {
    let result = SpotifyAuthCoordinator.authorizationCode(
        fromQuery: ["code": "the-code", "state": "expected"], expectedState: "expected"
    )
    #expect(try result.get() == "the-code")
}

@Test("a mismatched state fails the CSRF check, never yielding a code")
func spotifyAuthCodeCSRFMismatch() {
    let result = SpotifyAuthCoordinator.authorizationCode(
        fromQuery: ["code": "the-code", "state": "attacker"], expectedState: "expected"
    )
    #expect(throws: SpotifyPlaybackError.self) { try result.get() }
}

@Test("an error param (e.g. the user declined) fails the connect")
func spotifyAuthCodeErrorParam() {
    let result = SpotifyAuthCoordinator.authorizationCode(
        fromQuery: ["error": "access_denied", "state": "expected"], expectedState: "expected"
    )
    #expect(throws: SpotifyPlaybackError.self) { try result.get() }
}

@Test("a missing code fails even when the state matches")
func spotifyAuthCodeMissingCode() {
    let result = SpotifyAuthCoordinator.authorizationCode(
        fromQuery: ["state": "expected"], expectedState: "expected"
    )
    #expect(throws: SpotifyPlaybackError.self) { try result.get() }
}

@Test("the success response is well-formed HTTP with a matching Content-Length")
func spotifyHTTPResponse() throws {
    let response = SpotifyAuthCoordinator.httpResponse(html: SpotifyAuthCoordinator.successHTML)
    let text = String(decoding: response, as: UTF8.self)
    #expect(text.hasPrefix("HTTP/1.1 200 OK\r\n"))
    #expect(text.contains("Content-Type: text/html"))
    // The body follows the blank line, and its byte count matches the declared Content-Length.
    let parts = text.components(separatedBy: "\r\n\r\n")
    let body = try #require(parts.last)
    #expect(text.contains("Content-Length: \(Data(body.utf8).count)"))
    #expect(body.contains("Spotify connected"))
}

@Test("the redirect URI is the fixed loopback address the user registers")
func spotifyRedirectURI() async {
    let coordinator = SpotifyAuthCoordinator(secretStore: MockSecretStore(), port: 8888)
    #expect(coordinator.redirectURI == "http://127.0.0.1:8888/callback")
}

@Test("the loopback listener captures the callback query over a real socket and responds")
func spotifyLoopbackListenerCaptures() async throws {
    // Bind port 0 — the kernel hands back a free port, so this can never collide with an ephemeral
    // port some other process on the machine happens to hold. The redirect uses the assigned port.
    let listener = try SpotifyLoopbackListener(port: 0)
    let query = try await listener.awaitCallback(timeout: 5) { boundPort in
        // Fire the redirect once the listener is accepting; the response is irrelevant to capture.
        Task {
            guard let url = URL(string: "http://127.0.0.1:\(boundPort)/callback?code=real-code&state=real-state") else { return }
            _ = try? await URLSession.shared.data(from: url)
        }
    }
    #expect(query["code"] == "real-code")
    #expect(query["state"] == "real-state")
}
#endif
