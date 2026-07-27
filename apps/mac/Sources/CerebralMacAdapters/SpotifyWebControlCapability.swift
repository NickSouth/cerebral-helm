// Spotify playback control via the Web API (NIC-133) — the widget's play/pause/skip buttons.
#if canImport(AppKit)
import Foundation
import CerebralCore
import CerebralTools

/// Controls the user's Spotify playback through the Web API (NIC-133): `play`/`pause` (`PUT`),
/// `next`/`previous` (`POST`) on `/me/player/...`. A valid access token is resolved from the
/// ``SpotifyAuthSession`` (refreshing as needed) and rides the `Authorization: Bearer` header. A
/// `204` (or any 2xx) is applied; a **`404` (NO_ACTIVE_DEVICE)** is reported honestly as
/// `activeDevice: false` rather than an error, so the widget can say "start playback on a device"
/// instead of appearing broken. A `401`/`403` (token rejected, or Premium required for control) is a
/// `permissionDenied`; any other failure is `unavailable`. Controls are `external_write` but the
/// descriptor waives confirmation (owner: play/pause/skip is too low-stakes to prompt).
/// A small thread-safe hook the control capability fires after a successful command so the
/// now-playing widget re-polls at once (NIC-133), instead of waiting out the publisher's cadence.
/// Wired to the publisher's `refresh()` at app composition; a no-op until then (pre-Mac/tests).
/// `@unchecked Sendable` — its single field is guarded by a lock.
public final class SpotifyRefreshSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var action: (@Sendable () -> Void)?

    public init() {}

    public func setAction(_ action: @escaping @Sendable () -> Void) {
        lock.lock(); defer { lock.unlock() }
        self.action = action
    }

    func fire() {
        lock.lock(); let action = self.action; lock.unlock()
        action?()
    }
}

public struct SpotifyWebControlCapability: SpotifyControlCapability {
    private let session: URLSession
    private let host: String
    private let authSession: SpotifyAuthSession
    private let refreshSignal: SpotifyRefreshSignal?

    public init(
        authSession: SpotifyAuthSession,
        session: URLSession? = nil,
        host: String = "https://api.spotify.com",
        resourceTimeout: TimeInterval = 15,
        refreshSignal: SpotifyRefreshSignal? = nil
    ) {
        self.authSession = authSession
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForResource = resourceTimeout
            config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            self.session = URLSession(configuration: config)
        }
        self.host = host
        self.refreshSignal = refreshSignal
    }

    public func control(action: String) async throws -> SpotifyControlResult {
        let token: String
        do {
            token = try await authSession.accessToken()
        } catch {
            // Not connected / can't refresh → the control surface is honestly unavailable.
            throw NativeCapabilityError.unavailable
        }
        guard let request = Self.makeRequest(host: host, action: action, accessToken: token) else {
            throw NativeCapabilityError.unavailable
        }
        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw NativeCapabilityError.unavailable }
            let result = try Self.interpret(action: action, statusCode: http.statusCode)
            // Nudge the now-playing widget to re-poll shortly after: Spotify's player state lags a
            // skip by a few hundred ms, so a brief delay lets the new track settle before the refresh.
            if result.applied, let signal = refreshSignal {
                Task {
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    signal.fire()
                }
            }
            return result
        } catch let error as NativeCapabilityError {
            throw error
        } catch {
            throw NativeCapabilityError.unavailable
        }
    }

    // MARK: - Pure helpers (unit-tested)

    /// The request for a playback action, with the token in the `Authorization` header (never the
    /// URL). An unknown action yields nil — the contract's input enum already rejects it upstream.
    static func makeRequest(host: String, action: String, accessToken: String) -> URLRequest? {
        let route: (path: String, method: String)
        switch action {
        case "play": route = ("/v1/me/player/play", "PUT")
        case "pause": route = ("/v1/me/player/pause", "PUT")
        case "next": route = ("/v1/me/player/next", "POST")
        case "previous": route = ("/v1/me/player/previous", "POST")
        default: return nil
        }
        guard let url = URL(string: host + route.path) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = route.method
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    /// Maps a Spotify player response status to a result. 2xx applied; 404 = no active device
    /// (honest, not an error); 401/403 rejected/Premium-required → denied; else unavailable.
    static func interpret(action: String, statusCode: Int) throws -> SpotifyControlResult {
        switch statusCode {
        case 200..<300:
            return SpotifyControlResult(action: action, applied: true, activeDevice: true)
        case 404:
            return SpotifyControlResult(action: action, applied: false, activeDevice: false)
        case 401, 403:
            throw NativeCapabilityError.permissionDenied
        default:
            throw NativeCapabilityError.unavailable
        }
    }
}
#endif
