// The macOS composition must bind a real adapter to every capability slot.
//
// `ToolCapabilities.init` gives every slot a default of `Mock…Capability(matrix: .none)`, so
// forgetting to pass one **compiles cleanly** and fails only at runtime, as a tool that refuses
// everything. That is exactly how `mail.open` shipped dead: written, tested, and never wired, so
// every Gmail link in the daily brief and the email report did nothing at all.
//
// These tests fail on the omission itself rather than on any one tool's symptoms.
#if canImport(AppKit)
import Foundation
import Testing

import CerebralCore
import CerebralMacAdapters
import CerebralTools

private func macComposition() -> MacToolCapabilities.Composition {
    MacToolCapabilities.make(referenceStore: CommandReferenceStore(CommandReferences()))
}

@Test("no capability slot in the macOS composition is left on its mock default")
func macCompositionBindsEveryCapability() {
    let capabilities = macComposition().capabilities

    var mocked: [String] = []
    for child in Mirror(reflecting: capabilities).children {
        let typeName = String(describing: type(of: child.value))
        if typeName.hasPrefix("Mock") {
            mocked.append("\(child.label ?? "?") is \(typeName)")
        }
    }

    #expect(mocked.isEmpty, "unwired capability slots: \(mocked.joined(separator: ", "))")
}

@Test("the macOS composition declares mail.open natively available")
func macCompositionDeclaresMailOpen() {
    // The declaration is separate from the binding, and the two silently disagreeing is its own
    // failure mode: a bound capability the handshake reports unavailable, or the reverse.
    #expect(macComposition().capabilities.nativeCapabilityIDs.contains(CapabilityMatrix.Capability.mailOpen))
}

@Test("every declared native capability id is a real capability")
func declaredCapabilityIDsAreKnown() {
    let declared = macComposition().capabilities.nativeCapabilityIDs
    let unknown = declared.subtracting(CapabilityMatrix.Capability.all)
    #expect(unknown.isEmpty, "unknown capability ids declared: \(unknown.sorted())")
}
#endif
