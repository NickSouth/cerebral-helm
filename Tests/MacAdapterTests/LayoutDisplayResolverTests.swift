#if canImport(AppKit)
import Testing

import CerebralMacAdapters
import CerebralTools

private func display(_ id: String, primary: Bool = false, stable: Bool = true) -> LayoutDisplayResolver.Display {
    LayoutDisplayResolver.Display(id: id, primary: primary, stableIdentity: stable)
}

@Suite("LayoutDisplayResolver (NIC-142)")
struct LayoutDisplayResolverTests {
    private let displays = [
        display("primary-1", primary: true),
        display("external-2", primary: false)
    ]

    @Test("an explicit non-primary layout display resolves to secondary")
    func explicitSecondary() {
        let result = LayoutDisplayResolver.resolve(
            layoutDisplayID: "external-2", mainDisplayID: "system-primary", displays: displays
        )
        #expect(result == .secondary)
    }

    @Test("an explicit primary layout display resolves to primary")
    func explicitPrimary() {
        let result = LayoutDisplayResolver.resolve(
            layoutDisplayID: "primary-1", mainDisplayID: "system-primary", displays: displays
        )
        #expect(result == .primary)
    }

    @Test("the sentinel follows the main display")
    func sentinelFollowsMain() {
        // Main is the external display → the layout follows it to secondary.
        let result = LayoutDisplayResolver.resolve(
            layoutDisplayID: "system-primary", mainDisplayID: "external-2", displays: displays
        )
        #expect(result == .secondary)
    }

    @Test("an unset layout display with an unset main resolves to primary")
    func bothUnsetIsPrimary() {
        let result = LayoutDisplayResolver.resolve(
            layoutDisplayID: nil, mainDisplayID: nil, displays: displays
        )
        #expect(result == .primary)
    }

    @Test("a disconnected or unknown layout display degrades to primary")
    func disconnectedDegradesToPrimary() {
        let result = LayoutDisplayResolver.resolve(
            layoutDisplayID: "gone-3", mainDisplayID: "system-primary", displays: displays
        )
        #expect(result == .primary)
    }

    @Test("a non-stable-identity display is never targeted")
    func unstableIsIgnored() {
        let result = LayoutDisplayResolver.resolve(
            layoutDisplayID: "session-scoped",
            mainDisplayID: "system-primary",
            displays: [display("primary-1", primary: true), display("session-scoped", primary: false, stable: false)]
        )
        #expect(result == .primary)
    }
}
#endif
