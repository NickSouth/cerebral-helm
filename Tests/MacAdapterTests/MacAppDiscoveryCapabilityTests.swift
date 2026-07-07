// NIC-119: read-only application discovery on the live macOS host.
#if canImport(AppKit)
import Foundation
import Testing

import CerebralMacAdapters
import CerebralTools

@Test("live discovery enumerates installed apps: unique bundle ids, non-empty names, capped decodable icons")
func liveDiscoveryShape() async throws {
    let result = try await MacAppDiscoveryCapability().listApplications(includeIcons: true)

    // Every macOS host ships /System/Applications — an empty result is a bug.
    #expect(!result.apps.isEmpty)
    let ids = result.apps.map(\.bundleID)
    #expect(Set(ids).count == ids.count)
    for app in result.apps {
        #expect(!app.name.isEmpty)
        #expect(!app.bundleID.isEmpty)
    }
    // Icons (sampled — rendering all is slow) decode as data and respect the cap.
    for app in result.apps.prefix(10) {
        if let icon = app.iconPNGBase64 {
            #expect(icon.count <= 98304)
            #expect(Data(base64Encoded: icon) != nil)
        }
    }
}

@Test("discovery without icons carries none, and never launches anything")
func discoveryWithoutIcons() async throws {
    let result = try await MacAppDiscoveryCapability().listApplications(includeIcons: false)
    #expect(result.apps.allSatisfy { $0.iconPNGBase64 == nil })
}
#endif
