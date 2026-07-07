// NIC-89: login item seam + single-instance guard.
#if canImport(AppKit)
import AppKit
import ServiceManagement
import Testing

import CerebralMacAdapters

@Test("the live status read is safe and maps to a stable vocabulary")
func liveStatusReadIsSafe() {
    // Read-only: never registers. The test runner is unbundled, so the OS
    // reports whatever it honestly knows — the map must cover every case.
    let status = SMAppServiceLoginItem().status()
    #expect(["enabled", "requires-approval", "not-registered", "not-found"].contains(status.rawValue))
}

@Test("every SMAppService status maps to exactly one shell status")
func statusMappingIsTotal() {
    #expect(SMAppServiceLoginItem.map(.enabled) == .enabled)
    #expect(SMAppServiceLoginItem.map(.requiresApproval) == .requiresApproval)
    #expect(SMAppServiceLoginItem.map(.notRegistered) == .notRegistered)
    #expect(SMAppServiceLoginItem.map(.notFound) == .notFound)
}

@Test("the single-instance guard never matches this process or a nil bundle id")
func singleInstanceGuardExcludesSelf() {
    // The test runner has no other instance of its own bundle id running.
    #expect(SingleInstanceGuard.existingInstance(bundleID: Bundle.main.bundleIdentifier) == nil)
    #expect(SingleInstanceGuard.existingInstance(bundleID: nil) == nil)
    // Finder is always running and is not this process — the query itself works.
    #expect(SingleInstanceGuard.existingInstance(bundleID: "com.apple.finder") != nil)
}
#endif
