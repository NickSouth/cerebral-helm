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
        "native.hook.run", "system.metrics", "native.workspace.windows", "weather", "battery",
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

// MARK: - Permission gating (NIC-83, FR-SAF-07)

import CerebralTools

private struct FakePermissions: PermissionChecking {
    let statuses: [String: PermissionStatus]
    func status(of permissionID: String) -> PermissionStatus {
        statuses[permissionID] ?? .notRequired
    }
}

@Test("a denied permission degrades only its capability, with guidance instead of a prompt")
func deniedPermissionDegradesOnlyItsCapability() {
    let flags = CompositionCapabilities.bridgeCapabilities(
        phase: .macOS,
        nativeCapabilityIDs: ["app.open", "url.open", "system.status.read"],
        requiredPermissions: [
            "system.status.read": ["system_metrics_read"],
            "app.open": ["application_launch"],
        ],
        permissions: FakePermissions(statuses: ["system_metrics_read": .denied])
    )
    let byID = Dictionary(uniqueKeysWithValues: flags.map { ($0.id, $0) })

    #expect(byID["system.metrics"]?.available == false)
    #expect(byID["battery"]?.available == false)
    #expect(byID["system.metrics"]?.degradedReason?.isEmpty == false)
    // Unrelated, permission-satisfied capabilities stay available (portable
    // workflows remain available).
    #expect(byID["native.app.open"]?.available == true)
    #expect(byID["native.url.open"]?.available == true)
}

@Test("notDetermined is conservative (unavailable with guidance); granted and notRequired satisfy")
func permissionStatusMapping() {
    func metricsFlag(_ status: PermissionStatus) -> CerebralContracts.Capability? {
        let flags = CompositionCapabilities.bridgeCapabilities(
            phase: .macOS,
            nativeCapabilityIDs: ["system.status.read"],
            requiredPermissions: ["system.status.read": ["system_metrics_read"]],
            permissions: FakePermissions(statuses: ["system_metrics_read": status])
        )
        return flags.first { $0.id == "system.metrics" }
    }

    #expect(metricsFlag(.granted)?.available == true)
    #expect(metricsFlag(.notRequired)?.available == true)
    #expect(metricsFlag(.denied)?.available == false)
    #expect(metricsFlag(.notDetermined)?.available == false)
}

@Test("a known TCC permission's guidance carries the System Settings deep link")
func accessibilityGuidanceCarriesDeepLink() {
    let flags = CompositionCapabilities.bridgeCapabilities(
        phase: .macOS,
        nativeCapabilityIDs: ["app.open"],
        requiredPermissions: ["app.open": ["accessibility"]],
        permissions: FakePermissions(statuses: ["accessibility": .denied])
    )
    let reason = flags.first { $0.id == "native.app.open" }?.degradedReason ?? ""
    #expect(reason.contains("Accessibility"))
    #expect(reason.contains("x-apple.systempreferences:"))
}

@Test("descriptor permission metadata folds into the per-capability requirement map")
func descriptorPermissionMapFolds() throws {
    let descriptors = try ToolDescriptorCatalog.loadDescriptors(
        directory: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // RuntimeHostTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repository root
            .appendingPathComponent("packages/contracts/fixtures/valid/tools/descriptors", isDirectory: true)
    )
    let map = CompositionCapabilities.requiredPermissionsByCapability(descriptors)

    #expect(map["system.status.read"] == ["system_metrics_read"])
    #expect(map["app.open"] == ["application_launch"])
    #expect(map["hook.run"] == ["allowlisted_process_execution"])
}

@Test("a permission recheck reports exactly the transitioned capabilities and updates the handshake set")
func sessionCapabilityUpdateDiffs() throws {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // RuntimeHostTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // repository root
    let paths = try WorkspacePaths.temporary(repositoryRoot: repositoryRoot)
    let session = BridgeSession(
        runtime: try makeCommandRuntime(paths: paths),
        configDirectory: paths.configDirectory,
        capabilities: CompositionCapabilities.bridgeCapabilities(
            phase: .macOS,
            nativeCapabilityIDs: ["system.status.read"],
            requiredPermissions: ["system.status.read": ["system_metrics_read"]],
            permissions: FakePermissions(statuses: ["system_metrics_read": .denied])
        )
    )
    #expect(session.capabilities.first { $0.id == "system.metrics" }?.available == false)

    // The user grants the permission and returns to the app: recheck.
    let updated = CompositionCapabilities.bridgeCapabilities(
        phase: .macOS,
        nativeCapabilityIDs: ["system.status.read"],
        requiredPermissions: ["system.status.read": ["system_metrics_read"]],
        permissions: FakePermissions(statuses: ["system_metrics_read": .granted])
    )
    let changed = session.updateCapabilities(updated)

    #expect(Set(changed.map(\.id)) == ["system.metrics", "battery"])
    #expect(session.capabilities.first { $0.id == "system.metrics" }?.available == true)
    // A recheck with no transition reports nothing.
    #expect(session.updateCapabilities(updated).isEmpty)
}

@Test("a capability transition encodes as the reducer-shaped bridge.capability.changed event")
func capabilityChangedEventShape() throws {
    let capability = CerebralContracts.Capability(
        available: true, degradedReason: nil, id: "system.metrics", source: .native
    )
    let event = BridgeEventFactory.capabilityChangedEvent(
        capability, id: "brevt_captest00000001", timestamp: Date(timeIntervalSinceReferenceDate: 0)
    )
    let json = String(decoding: try BridgeMessageCoding.encoder().encode(event), as: UTF8.self)

    #expect(event.type == .bridgeCapabilityChanged)
    #expect(json.contains("\"capability\""))
    #expect(json.contains("\"id\":\"system.metrics\""))
    #expect(json.contains("\"available\":true"))
}
