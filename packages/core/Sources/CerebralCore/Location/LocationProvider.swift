import Foundation

/// A resolved geographic coordinate (NIC-169). Coarse by design — the weather widget needs
/// only city-level accuracy — and provider-neutral, so the portable core never imports a
/// platform location framework.
public struct LocationReading: Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// Why a location could not be resolved. `permissionDenied` is the user declining (or
/// restricting) the location grant — the caller degrades weather to an honest "Location
/// unavailable" with guidance, never a prompt loop (FR-SAF-07). `unavailable` covers a
/// missing fix, a timeout, or any platform error.
public enum LocationError: Error, Equatable, Sendable {
    case permissionDenied
    case unavailable(String)
}

/// Port that resolves the device's current coordinate (NIC-169). Async because a real
/// implementation waits on the platform location service; the mock resolves immediately.
/// The concrete macOS implementation (`CoreLocationProvider`) prompts for authorization at
/// point of use and lives in the Mac adapter layer, so this contract stays portable and
/// permission-agnostic. Throws ``LocationError`` on denial or failure — never a fabricated
/// coordinate.
public protocol LocationProvider: Sendable {
    func currentLocation() async throws -> LocationReading
}

/// A fixed-outcome ``LocationProvider`` for pre-Mac builds and tests: it yields the reading
/// (or throws the error) it was constructed with, without touching any platform service.
public struct MockLocationProvider: LocationProvider {
    private let outcome: Result<LocationReading, LocationError>

    public init(reading: LocationReading) {
        self.outcome = .success(reading)
    }

    public init(error: LocationError) {
        self.outcome = .failure(error)
    }

    public func currentLocation() async throws -> LocationReading {
        try outcome.get()
    }
}
