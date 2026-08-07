import Foundation
import Testing

import CerebralCore

/// NIC-169 Increment 3: the portable location-provider contract. The real CoreLocation
/// implementation lives in the Mac adapter; here the mock stands in for pre-Mac/tests.

@Test("the mock location provider yields its constructed reading")
func locationMockYieldsReading() async throws {
    let provider = MockLocationProvider(reading: LocationReading(latitude: 37.7749, longitude: -122.4194))
    let reading = try await provider.currentLocation()
    #expect(reading.latitude == 37.7749)
    #expect(reading.longitude == -122.4194)
}

@Test("the mock location provider throws its constructed error")
func locationMockThrowsError() async {
    let provider = MockLocationProvider(error: .permissionDenied)
    await #expect(throws: LocationError.permissionDenied) {
        try await provider.currentLocation()
    }
}

@Test("LocationError distinguishes a denied permission from an unavailable fix")
func locationErrorCasesAreDistinct() {
    #expect(LocationError.permissionDenied != LocationError.unavailable("no fix"))
    #expect(LocationError.unavailable("x") == LocationError.unavailable("x"))
}
