import Foundation
import Testing

import CerebralContracts
import CerebralCore

/// AC-22.1: command and event models round-trip through the canonical schemas.

private func fixturesRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // CoreModelTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // repository root
        .appendingPathComponent("packages/contracts/fixtures", isDirectory: true)
}

private func jsonFiles(in relativePath: String) throws -> [URL] {
    let directory = fixturesRoot().appendingPathComponent(relativePath, isDirectory: true)
    return try FileManager.default
        .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "json" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
}

@Test("valid command envelope fixtures decode, re-encode, and decode equivalently")
func commandEnvelopesRoundTrip() throws {
    let decoder = CommandCoding.makeDecoder()
    let encoder = CommandCoding.makeEncoder()
    let files = try jsonFiles(in: "valid/commands")
    #expect(!files.isEmpty)

    for file in files {
        let data = try Data(contentsOf: file)
        let value = try decoder.decode(CommandEnvelope.self, from: data)
        let again = try decoder.decode(CommandEnvelope.self, from: encoder.encode(value))

        #expect(value.id == again.id, "\(file.lastPathComponent)")
        #expect(value.source == again.source, "\(file.lastPathComponent)")
        #expect(value.rawInput == again.rawInput, "\(file.lastPathComponent)")
        #expect(value.timestamp == again.timestamp, "\(file.lastPathComponent)")
        #expect(value.privacy.sensitivity == again.privacy.sensitivity, "\(file.lastPathComponent)")
        #expect(CommandIdentity.isValidCommandIdentifier(value.id), "\(file.lastPathComponent)")
    }
}

@Test("valid lifecycle event fixtures round-trip")
func lifecycleEventsRoundTrip() throws {
    let decoder = CommandCoding.makeDecoder()
    let encoder = CommandCoding.makeEncoder()
    let files = try jsonFiles(in: "valid/lifecycle")
    #expect(!files.isEmpty)

    for file in files {
        let data = try Data(contentsOf: file)
        let value = try decoder.decode(CommandLifecycleEvent.self, from: data)
        let again = try decoder.decode(CommandLifecycleEvent.self, from: encoder.encode(value))

        #expect(value.id == again.id, "\(file.lastPathComponent)")
        #expect(value.commandID == again.commandID, "\(file.lastPathComponent)")
        #expect(value.previousStatus == again.previousStatus, "\(file.lastPathComponent)")
        #expect(value.currentStatus == again.currentStatus, "\(file.lastPathComponent)")
        #expect(value.timestamp == again.timestamp, "\(file.lastPathComponent)")
        #expect(CommandIdentity.isValidEventIdentifier(value.id), "\(file.lastPathComponent)")
    }
}

@Test("valid terminal result fixtures round-trip")
func terminalResultsRoundTrip() throws {
    let decoder = CommandCoding.makeDecoder()
    let encoder = CommandCoding.makeEncoder()
    let files = try jsonFiles(in: "valid/results")
    #expect(!files.isEmpty)

    for file in files {
        let data = try Data(contentsOf: file)
        let value = try decoder.decode(CommandTerminalResult.self, from: data)
        let again = try decoder.decode(CommandTerminalResult.self, from: encoder.encode(value))

        #expect(value.commandID == again.commandID, "\(file.lastPathComponent)")
        #expect(value.status == again.status, "\(file.lastPathComponent)")
        #expect(value.summary == again.summary, "\(file.lastPathComponent)")
        #expect(value.completedAt == again.completedAt, "\(file.lastPathComponent)")
    }
}

@Test("generated DTO convenience initializers decode fractional-second fixtures")
func generatedInitDecodesFractionalSeconds() throws {
    // Exercises the quicktype-generated public init(data:)/jsonData() helpers
    // directly (not CommandCoding) to prove the generated date strategy now
    // parses fractional-second timestamps such as 2026-06-23T16:00:02.000Z.
    let file = fixturesRoot()
        .appendingPathComponent("valid/commands/cli-command-envelope.json")
    let data = try Data(contentsOf: file)

    let envelope = try CerebralHelmCommandEnvelope(data: data)
    #expect(envelope.id == "cmd_000000000000000000000003")

    let reference = ISO8601DateFormatter()
    reference.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    #expect(envelope.timestamp == reference.date(from: "2026-06-23T16:00:02.000Z"))

    // jsonData() emits fractional seconds, so init(data:) round-trips it.
    let again = try CerebralHelmCommandEnvelope(data: envelope.jsonData())
    #expect(again.timestamp == envelope.timestamp)
}

@Test("an unknown command source is rejected on decode")
func unknownSourceIsRejected() throws {
    let file = fixturesRoot()
        .appendingPathComponent("invalid/commands/unknown-source-command-envelope.json")
    let data = try Data(contentsOf: file)
    let decoder = CommandCoding.makeDecoder()

    #expect(throws: (any Error).self) {
        _ = try decoder.decode(CommandEnvelope.self, from: data)
    }
}
