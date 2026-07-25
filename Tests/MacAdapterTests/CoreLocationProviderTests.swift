// NIC-169 Increment 3: CoreLocation authorization → logical permission mapping.
#if canImport(CoreLocation)
import CoreLocation
import Testing

import CerebralMacAdapters
import CerebralTools

@Test("an authorized location status maps to granted (satisfies the requirement)")
func locationAuthorizedMapsGranted() {
    // `.authorizedWhenInUse` is unavailable as a value on macOS (it is still handled in the
    // provider's case patterns for shared code); `.authorizedAlways` is the macOS grant.
    #expect(CoreLocationProvider.permissionStatus(from: .authorizedAlways) == .granted)
    #expect(CoreLocationProvider.permissionStatus(from: .authorizedAlways).satisfiesRequirement)
}

@Test("a denied or restricted location status maps to denied (degrades with guidance)")
func locationDeniedMapsDenied() {
    #expect(CoreLocationProvider.permissionStatus(from: .denied) == .denied)
    #expect(CoreLocationProvider.permissionStatus(from: .restricted) == .denied)
    #expect(!CoreLocationProvider.permissionStatus(from: .denied).satisfiesRequirement)
}

@Test("an undetermined location status maps to notDetermined, not a silent pass")
func locationNotDeterminedMapping() {
    #expect(CoreLocationProvider.permissionStatus(from: .notDetermined) == .notDetermined)
    #expect(!CoreLocationProvider.permissionStatus(from: .notDetermined).satisfiesRequirement)
}
#endif
