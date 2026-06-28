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

/// Canonical bytes for a free-form JSONAny payload.
///
/// `JSONAny` is a reference type with no `Equatable`/`Hashable` conformance,
/// so two structurally identical payloads compare unequal by identity. The
/// shared `CommandCoding` encoder uses `.sortedKeys`, so re-encoding a payload
/// yields deterministic bytes that can stand in for a deep value comparison.
private func canonicalPayloadBytes(_ payload: [String: JSONAny]) throws -> Data {
    try CommandCoding.makeEncoder().encode(payload)
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
        // payload is free-form JSONAny (the field CommandRedaction protects);
        // JSONAny is not Equatable, so compare canonical re-encoded bytes.
        #expect(
            try canonicalPayloadBytes(value.payload) == canonicalPayloadBytes(again.payload),
            "\(file.lastPathComponent)"
        )
        #expect(value.correlationID == again.correlationID, "\(file.lastPathComponent)")
        #expect(CommandIdentity.isValidCommandIdentifier(value.id), "\(file.lastPathComponent)")
    }
}

/// AC-22.1 (extended): a non-null correlationId matching `^(cmd|corr)_` and a
/// nested/non-trivial payload survive the encode -> decode round-trip. The
/// fixtures all carry `correlationId: null` and flat payloads, so this case is
/// not exercised by `commandEnvelopesRoundTrip`; the envelope is built in-code
/// rather than as a fixture to avoid touching the fixture schema mapping.
@Test("nested payload and non-null correlationId survive the command-envelope round-trip")
func commandEnvelopeNestedPayloadRoundTrip() throws {
    let decoder = CommandCoding.makeDecoder()
    let encoder = CommandCoding.makeEncoder()

    let json = Data("""
    {
      "schemaVersion": "1.0.0",
      "id": "cmd_000000000000000000000099",
      "type": "command.submit",
      "source": "cli",
      "rawInput": "status",
      "timestamp": "2026-06-23T16:00:02.000Z",
      "correlationId": "corr_000000000000000000000042",
      "payload": {
        "toolId": "system.status.read",
        "filters": {
          "scope": "project",
          "tags": ["alpha", "beta"],
          "limit": 5,
          "verbose": true
        },
        "targets": [
          { "kind": "file", "path": "a/b.txt" },
          { "kind": "url", "value": "https://example.com/x" }
        ]
      },
      "privacy": {
        "sensitivity": "private",
        "cloudPolicy": "deny"
      }
    }
    """.utf8)

    let value = try decoder.decode(CommandEnvelope.self, from: json)
    #expect(CommandIdentity.isValidCommandIdentifier(value.id))
    #expect(value.correlationID == "corr_000000000000000000000042")

    let again = try decoder.decode(CommandEnvelope.self, from: encoder.encode(value))

    #expect(value.correlationID == again.correlationID)
    #expect(
        try canonicalPayloadBytes(value.payload) == canonicalPayloadBytes(again.payload)
    )
    // Sanity-check the payload genuinely round-trips the nested structure and is
    // not silently flattened to an empty/degenerate object.
    #expect(again.payload["filters"] != nil)
    #expect(again.payload["targets"] != nil)
    #expect(try canonicalPayloadBytes(again.payload) == canonicalPayloadBytes(value.payload))
}

/// The `correlationId: null` case must also round-trip back to nil, mirroring
/// every shipped fixture while exercising the in-code construction path.
@Test("null correlationId round-trips to nil for the command envelope")
func commandEnvelopeNullCorrelationRoundTrip() throws {
    let decoder = CommandCoding.makeDecoder()
    let encoder = CommandCoding.makeEncoder()

    let json = Data("""
    {
      "schemaVersion": "1.0.0",
      "id": "cmd_000000000000000000000098",
      "type": "command.submit",
      "source": "cli",
      "rawInput": "status",
      "timestamp": "2026-06-23T16:00:02.000Z",
      "correlationId": null,
      "payload": {
        "nested": { "a": 1, "b": [true, null, "x"] }
      },
      "privacy": {
        "sensitivity": "private",
        "cloudPolicy": "deny"
      }
    }
    """.utf8)

    let value = try decoder.decode(CommandEnvelope.self, from: json)
    #expect(value.correlationID == nil)

    let again = try decoder.decode(CommandEnvelope.self, from: encoder.encode(value))
    #expect(again.correlationID == nil)
    #expect(
        try canonicalPayloadBytes(value.payload) == canonicalPayloadBytes(again.payload)
    )
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
