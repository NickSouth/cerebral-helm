// Google OAuth connect: PKCE + a loopback listener + the system browser (Gmail integration).
#if canImport(AppKit)
import Foundation
import CerebralCore
import CerebralTools

/// The result of a successful connect — the granted scope and the access-token expiry. The tokens
/// themselves are persisted to the Keychain and never returned, so they cannot reach the UI layer.
public struct GoogleConnection: Sendable, Equatable {
    public let scope: String?
    public let expiresAt: Date
    /// Whether a refresh token came back. **False is a warning, not a success**: without one the
    /// connection dies in an hour and cannot renew itself, which is what `access_type=offline` +
    /// `prompt=consent` exist to prevent. The surface says so rather than reporting a clean connect.
    public let canRefresh: Bool
}

/// Runs the Google Authorization Code + PKCE connect flow on this Mac: generate PKCE, bind a
/// loopback listener, open the browser to Google's consent screen, capture the redirected `?code`,
/// exchange it for tokens, and persist them to the Keychain.
///
/// The redirect URI is a **fixed** loopback address. Google's native-app documentation says the
/// redirect "must exactly match one of the authorized redirect URIs" configured for the client, so
/// an ephemeral port would be a gamble on how strictly that is enforced for Desktop clients — a
/// fixed port is correct under either reading. Port 8890 avoids Spotify's 8888 and the Canvas
/// ingest server's 8899.
///
/// Request parsing, the CSRF state check, and response building are pure static helpers (unit
/// tested); the full round trip is browser-interactive and is verified by the manual OAuth smoke.
public struct GoogleAuthCoordinator: Sendable {
    private let exchange: GoogleTokenExchange
    private let secretStore: any SecretStoreManaging
    private let workspace: any WorkspaceOpening
    private let port: UInt16
    private let callbackPath: String
    private let timeout: TimeInterval
    /// Resolves the connected account's own address from a fresh access token. Injected so the
    /// connect flow is testable without a network call.
    private let addressLookup: @Sendable (String) async -> String?

    public init(
        exchange: GoogleTokenExchange = GoogleTokenExchange(),
        secretStore: any SecretStoreManaging,
        workspace: any WorkspaceOpening = SystemWorkspace(),
        port: UInt16 = 8890,
        callbackPath: String = "/callback",
        timeout: TimeInterval = 180,
        addressLookup: @escaping @Sendable (String) async -> String? = {
            await GmailAPIProvider.fetchAddress(accessToken: $0)
        }
    ) {
        self.exchange = exchange
        self.secretStore = secretStore
        self.workspace = workspace
        self.port = port
        self.callbackPath = callbackPath
        self.timeout = timeout
        self.addressLookup = addressLookup
    }

    /// The loopback redirect URI. Registered in the Google client only if the console offers the
    /// field — Desktop clients generally do not, because loopback is implied for them.
    public var redirectURI: String { "http://127.0.0.1:\(port)\(callbackPath)" }

    /// Reads the stored Client ID and runs the flow. The Client ID lives in the **Keychain**, not
    /// in `.env`: a built, distributed `.app` cannot read the developer's environment file, which
    /// the Spotify integration established the hard way (NIC-133 increment 6).
    public func connect(now: Date = Date()) async throws -> GoogleConnection {
        let clientID = try await storedClientID()
        return try await connect(clientID: clientID, now: now)
    }

    public func connect(clientID: String, now: Date = Date()) async throws -> GoogleConnection {
        // Optional by design: a Desktop client has a secret and Google's token endpoint requires
        // it, while an Android/iOS/Chrome client has none. Absent simply means "don't send one".
        let clientSecret = try? await secretStore.readValue(
            reference: GoogleAuthSession.clientSecretReference
        )
        let verifier = OAuthPKCE.makeVerifier()
        let challenge = OAuthPKCE.challenge(for: verifier)
        let state = OAuthPKCE.makeState()
        guard let authorizeURL = exchange.authorizeURL(
            clientID: clientID, redirectURI: redirectURI, challenge: challenge, state: state
        ) else {
            throw GoogleAuthError.providerFailed("Could not build the Google authorize URL.")
        }

        let listener = try LoopbackAuthListener(
            port: port, responseHTML: LoopbackAuthListener.successHTML(title: "Gmail connected")
        )
        let workspace = self.workspace
        let query: [String: String]
        do {
            query = try await listener.awaitCallback(timeout: timeout) { _ in
                // Open the browser only once the listener is accepting, so the redirect cannot
                // race the bind.
                Task { try? await workspace.openURL(authorizeURL) }
            }
        } catch let error as LoopbackAuthError {
            throw Self.authError(for: error)
        }

        let code = try Self.authorizationCode(fromQuery: query, expectedState: state).get()
        let tokens = try await exchange.exchange(
            code: code, verifier: verifier, redirectURI: redirectURI,
            clientID: clientID, clientSecret: clientSecret, now: now
        )
        // Which account this grant is for, so a link opens *that* mailbox in the Chrome profile
        // signed into it. Best-effort: a nil address costs the addressing refinement, not the
        // connection, so it never fails a consent the user just gave.
        let tagged = tokens.withAddress(await addressLookup(tokens.accessToken))
        try await GoogleTokenBlob.save(tagged, to: secretStore)
        return GoogleConnection(
            scope: tagged.scope,
            expiresAt: tagged.expiresAt,
            canRefresh: tagged.refreshToken != nil
        )
    }

    /// Removes the stored grant. Missing tokens are not an error — disconnecting an already
    /// disconnected account is a no-op success.
    ///
    /// This deletes the **local** copy only. It does not revoke the grant at Google, and the
    /// surface must not imply otherwise; revoking is done at myaccount.google.com/permissions.
    public func disconnect() async throws {
        do {
            try await secretStore.delete(reference: GoogleTokenBlob.reference)
        } catch {
            // Already absent — nothing to remove.
        }
    }

    // MARK: - Pure helpers (unit-tested)

    private func storedClientID() async throws -> String {
        guard
            let value = try? await secretStore.readValue(reference: GoogleAuthSession.clientIDReference),
            !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw GoogleAuthError.clientIDMissing
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Google's wording for a provider-neutral listener failure.
    static func authError(for error: LoopbackAuthError) -> GoogleAuthError {
        switch error {
        case let .bindFailed(detail):
            return .providerFailed("The loopback listener failed: \(detail)")
        case .timedOut:
            // The browser was left open, or consent was never completed. Not a fault worth alarming
            // about — the user simply did not finish.
            return .cancelled
        case .closedEarly:
            return .providerFailed("The authorization callback closed before a request was received.")
        }
    }

    /// Validates the callback and extracts the authorization code.
    ///
    /// The `state` check is the CSRF defence: a callback that did not originate from the authorize
    /// request this process started is refused even if it carries a usable-looking code.
    static func authorizationCode(
        fromQuery query: [String: String], expectedState: String
    ) -> Result<String, GoogleAuthError> {
        if let error = query["error"] {
            // `access_denied` is the ordinary "user said no", or a Testing-mode project the account
            // is not a listed test user of.
            return error == "access_denied"
                ? .failure(.cancelled)
                : .failure(.providerFailed("Google did not grant authorization (\(error))."))
        }
        guard query["state"] == expectedState else {
            return .failure(.providerFailed("The authorization response failed the CSRF state check."))
        }
        guard let code = query["code"], !code.isEmpty else {
            return .failure(.providerFailed("The authorization response contained no code."))
        }
        return .success(code)
    }
}
#endif
