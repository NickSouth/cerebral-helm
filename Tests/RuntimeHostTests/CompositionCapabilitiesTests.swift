import Foundation
import Testing

import CerebralContracts
import CerebralCore
import CerebralRuntimeHost

/// The handshake capability flags are derived from composition (FR-SHL-06),
/// not hardcoded: mock/pre-Mac compositions report every native capability
/// unavailable; a macOS composition reports exactly the natively-bound slots.

@Test("the pre-Mac mock composition derives the honest pre-adapter set")
func preMacDerivationMatchesPreAdapterDefault() {
    let flags = CompositionCapabilities.bridgeCapabilities(phase: .preMac, nativeCapabilityIDs: [])

    #expect(flags.map(\.id) == [
        "bridge.bootstrap", "native.app.open", "native.url.open",
        "native.hook.run", "system.metrics", "weather", "battery",
    ])
    let bootstrap = flags.first { $0.id == "bridge.bootstrap" }
    #expect(bootstrap?.available == true)
    #expect(bootstrap?.source == .native)
    for flag in flags where flag.id != "bridge.bootstrap" {
        #expect(flag.available == false, Comment(rawValue: flag.id))
        #expect(flag.source == .unavailable, Comment(rawValue: flag.id))
        #expect(flag.degradedReason?.isEmpty == false, Comment(rawValue: flag.id))
    }
}

@Test("a macOS composition reports exactly its natively-bound capabilities available")
func macOSDerivationReflectsNativeBindings() {
    let flags = CompositionCapabilities.bridgeCapabilities(
        phase: .macOS,
        nativeCapabilityIDs: ["app.open", "url.open"]
    )
    let byID = Dictionary(uniqueKeysWithValues: flags.map { ($0.id, $0) })

    #expect(byID["native.app.open"]?.available == true)
    #expect(byID["native.app.open"]?.source == .native)
    #expect(byID["native.app.open"]?.degradedReason == nil)
    #expect(byID["native.url.open"]?.available == true)
    // Unbound slots stay honestly unavailable.
    #expect(byID["native.hook.run"]?.available == false)
    #expect(byID["system.metrics"]?.available == false)
    #expect(byID["battery"]?.available == false)
    // No weather provider exists in the MVP regardless of composition.
    #expect(byID["weather"]?.available == false)
}

@Test("system metrics and battery flags ride the system-status binding")
func systemStatusBindingFlipsMetricsAndBattery() {
    let flags = CompositionCapabilities.bridgeCapabilities(
        phase: .macOS,
        nativeCapabilityIDs: ["system.status.read"]
    )
    let byID = Dictionary(uniqueKeysWithValues: flags.map { ($0.id, $0) })

    #expect(byID["system.metrics"]?.available == true)
    #expect(byID["battery"]?.available == true)
    #expect(byID["native.app.open"]?.available == false)
}

@Test("a native binding declared in the pre-Mac phase stays unavailable")
func preMacPhaseGatesNativeDeclarations() {
    // The phase is part of the honesty check: mock/pre-Mac compositions cannot
    // advertise native capabilities even if a bundle claims them.
    let flags = CompositionCapabilities.bridgeCapabilities(
        phase: .preMac,
        nativeCapabilityIDs: ["app.open", "url.open", "hook.run", "system.status.read"]
    )

    #expect(flags.allSatisfy { $0.id == "bridge.bootstrap" || !$0.available })
}
