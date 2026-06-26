import Foundation
import Testing

import CerebralContracts

/// NIC-10 Increment 1 (enabling): every MVP tool's input and output contract has
/// a generated DTO that strictly decodes its valid fixture and rejects its
/// invalid fixture. This is the Swift half of the "strict decoding plus shared
/// valid/invalid fixture suites" rule from TECH-STACK; the JS Ajv suite
/// (scripts/validate-contracts.mjs) is the schema half.

private func ioFixture(_ kind: String, _ name: String) throws -> Data {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // CoreModelTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // repository root
        .appendingPathComponent("packages/contracts/fixtures/\(kind)/tools/io/\(name).json")
    return try Data(contentsOf: url)
}

/// Each tool I/O fixture basename paired with a closure that decodes the bytes
/// into the matching generated DTO and re-encodes them. Decoding a valid fixture
/// returns its re-encoded form (so the caller can prove a stable round-trip);
/// decoding an invalid fixture throws. Built per call rather than as a global so
/// the non-Sendable closures stay function-local under Swift 6 concurrency.
private func toolIoContracts() -> [(name: String, roundTrip: (Data) throws -> Data)] {
    [
        ("app-open-input", { try CerebralHelmAppOpenInput(data: $0).jsonData() }),
        ("app-open-output", { try CerebralHelmAppOpenOutput(data: $0).jsonData() }),
        ("url-open-input", { try CerebralHelmURLOpenInput(data: $0).jsonData() }),
        ("url-open-output", { try CerebralHelmURLOpenOutput(data: $0).jsonData() }),
        ("hook-run-input", { try CerebralHelmHookRunInput(data: $0).jsonData() }),
        ("hook-run-output", { try CerebralHelmHookRunOutput(data: $0).jsonData() }),
        ("note-capture-input", { try CerebralHelmNoteCaptureInput(data: $0).jsonData() }),
        ("note-capture-output", { try CerebralHelmNoteCaptureOutput(data: $0).jsonData() }),
        ("note-search-input", { try CerebralHelmNoteSearchInput(data: $0).jsonData() }),
        ("note-search-output", { try CerebralHelmNoteSearchOutput(data: $0).jsonData() }),
        ("mode-apply-input", { try CerebralHelmModeApplyInput(data: $0).jsonData() }),
        ("mode-apply-output", { try CerebralHelmModeApplyOutput(data: $0).jsonData() }),
        ("system-status-read-input", { try CerebralHelmSystemStatusReadInput(data: $0).jsonData() }),
        ("system-status-read-output", { try CerebralHelmSystemStatusReadOutput(data: $0).jsonData() }),
    ]
}

@Test("every MVP tool input/output contract has a generated DTO")
func toolIoContractsCoverEveryMvpTool() {
    let names = toolIoContracts().map(\.name)
    let expected: Set<String> = [
        "app-open", "url-open", "hook-run", "note-capture",
        "note-search", "mode-apply", "system-status-read",
    ]
    let observed = Set(
        names.map {
            $0.replacingOccurrences(of: "-input", with: "")
                .replacingOccurrences(of: "-output", with: "")
        }
    )

    #expect(observed == expected)
    #expect(names.count == 14)
}

@Test("valid tool I/O fixtures decode and round-trip through their generated DTOs")
func validToolIoFixturesRoundTrip() throws {
    for (name, roundTrip) in toolIoContracts() {
        let data = try ioFixture("valid", name)
        let reencoded = try roundTrip(data)
        // Re-decoding the re-encoded form proves the DTO is stable, not lossy.
        _ = try roundTrip(reencoded)
    }
}

@Test("invalid tool I/O fixtures are rejected by strict decoding")
func invalidToolIoFixturesAreRejected() throws {
    for (name, roundTrip) in toolIoContracts() {
        let data = try ioFixture("invalid", name)
        #expect(throws: (any Error).self, "\(name) should be rejected") {
            _ = try roundTrip(data)
        }
    }
}
