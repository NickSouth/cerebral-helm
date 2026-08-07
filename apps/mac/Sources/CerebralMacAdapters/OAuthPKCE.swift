// PKCE primitives, shared by every OAuth provider this app connects to.
#if canImport(AppKit)
import CryptoKit
import Foundation

/// PKCE (RFC 7636) primitives for the Authorization Code flow.
///
/// Extracted from the Spotify implementation when Gmail became the second provider (2026-08-04).
/// **This duplication would have been the bad kind** — unlike `google.search` / `youtube.search`,
/// where two near-identical adapters exist *because* the destination host being a literal constant
/// in each is the safety property. Nothing here chooses a destination: these are three pure
/// functions over random bytes and a hash, and two copies could only ever drift apart.
///
/// A native desktop app cannot safely hold a client secret, so PKCE replaces it: a high-entropy
/// `code_verifier` is kept locally and only its SHA-256 `code_challenge` travels in the authorize
/// request. The provider requires the original verifier at token-exchange time, proving the same
/// client that started the flow is the one finishing it.
public enum OAuthPKCE {
    /// A fresh `code_verifier`: 64 random bytes as base64url (86 chars, within RFC 7636's 43–128),
    /// drawn from the system CSPRNG. Every character is in the unreserved set by construction.
    public static func makeVerifier() -> String {
        base64URLEncode(randomBytes(64))
    }

    /// The `code_challenge` for a verifier: base64url(SHA-256(verifier)), no padding — the exact
    /// transform the provider recomputes and compares at token exchange.
    public static func challenge(for verifier: String) -> String {
        let digest = CryptoKit.SHA256.hash(data: Data(verifier.utf8))
        return base64URLEncode(Data(digest))
    }

    /// A random CSRF `state` nonce (16 bytes, base64url) round-tripped through the authorize
    /// request and verified on the redirect callback.
    public static func makeState() -> String {
        base64URLEncode(randomBytes(16))
    }

    private static func randomBytes(_ count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        for index in bytes.indices { bytes[index] = UInt8.random(in: UInt8.min...UInt8.max) }
        return Data(bytes)
    }

    /// URL-safe base64 with padding stripped (RFC 4648 §5), as PKCE requires.
    static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// `application/x-www-form-urlencoded` body with each key and value percent-encoded against the
    /// unreserved set and sorted for a deterministic order (aids testing; order is irrelevant to
    /// the server). Shared for the same reason as the rest of this file.
    static func formURLEncoded(_ parameters: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let encoded = parameters.sorted { $0.key < $1.key }.map { key, value -> String in
            let ek = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let ev = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(ek)=\(ev)"
        }
        return Data(encoded.joined(separator: "&").utf8)
    }
}
#endif
