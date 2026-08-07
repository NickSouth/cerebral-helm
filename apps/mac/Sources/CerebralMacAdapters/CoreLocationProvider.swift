// CoreLocation-backed location resolution for the weather widget (NIC-169).
#if canImport(CoreLocation)
@preconcurrency import CoreLocation
import Foundation
import CerebralCore
import CerebralTools

/// Resolves the device's coordinate via CoreLocation (NIC-169), prompting for the
/// when-in-use grant **at point of use** — the house rule for TCC permissions (the same
/// one `MacPermissionChecker`/`AXWindowCapability` follow): nothing is requested at launch.
///
/// A one-shot fix: it asks for authorization if undetermined, then requests a single
/// location and resolves the awaiting call with the first fix (or an honest error). Coarse
/// accuracy (kilometre) is all the bottom-bar weather needs and keeps the fix fast and cheap.
/// Main-actor isolated because `CLLocationManager` must be created and used on a thread with
/// a run loop and delivers its delegate callbacks there; that isolation also makes the class
/// `Sendable` for the ``LocationProvider`` conformance.
@MainActor
public final class CoreLocationProvider: NSObject, LocationProvider {
    private let manager: CLLocationManager
    private var pending: CheckedContinuation<LocationReading, Error>?
    /// True while we are waiting for the user's answer to the authorization prompt, so a
    /// later authorization change knows to proceed to the fix rather than ignore it.
    private var awaitingAuthorization = false

    public override init() {
        manager = CLLocationManager()
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    public func currentLocation() async throws -> LocationReading {
        try await withCheckedThrowingContinuation { continuation in
            guard pending == nil else {
                continuation.resume(throwing: LocationError.unavailable("A location request is already in progress."))
                return
            }
            pending = continuation
            start()
        }
    }

    /// Drives the state machine from the current authorization: grant → fix, undetermined →
    /// prompt (then fix on grant), denied/restricted → honest failure.
    private func start() {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .notDetermined:
            awaitingAuthorization = true
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            finish(.failure(LocationError.permissionDenied))
        @unknown default:
            finish(.failure(LocationError.permissionDenied))
        }
    }

    private func finish(_ result: Result<LocationReading, Error>) {
        guard let continuation = pending else { return }
        pending = nil
        awaitingAuthorization = false
        continuation.resume(with: result)
    }

    /// Maps a CoreLocation authorization status onto the logical ``PermissionStatus`` the
    /// composition layer reads (FR-SHL-06). Pure and side-effect-free so it is unit-testable
    /// without the platform; `MacPermissionChecker` reads the live status through it.
    /// `nonisolated` so the (nonisolated) permission checker can call it synchronously.
    public nonisolated static func permissionStatus(from status: CLAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            return .granted
        case .denied, .restricted:
            return .denied
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .notDetermined
        }
    }
}

// `@preconcurrency`: CoreLocation delivers these delegate callbacks on the thread the manager
// was created on — the main actor here — so the main-actor-isolated methods are safe; the
// annotation validates that at runtime instead of rejecting the conformance at compile time.
extension CoreLocationProvider: @preconcurrency CLLocationManagerDelegate {
    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard awaitingAuthorization else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            awaitingAuthorization = false
            manager.requestLocation()
        case .denied, .restricted:
            finish(.failure(LocationError.permissionDenied))
        case .notDetermined:
            break // still waiting on the user's choice
        @unknown default:
            finish(.failure(LocationError.permissionDenied))
        }
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            finish(.failure(LocationError.unavailable("No location fix returned.")))
            return
        }
        finish(.success(LocationReading(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )))
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(.failure(LocationError.unavailable(error.localizedDescription)))
    }
}
#endif
