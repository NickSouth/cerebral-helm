import Foundation
import Testing

import CerebralContracts
import CerebralCore

/// NIC-34 (PRE-SAFETY-7): schema-aware logging redaction and secret canaries.
///
/// AC-34.1 canaries never appear in logs/fixtures/diagnostics; AC-34.2 redaction
/// preserves useful non-sensitive context; AC-34.3 secret references stay logical.

private func descriptor(_ id: String) throws -> CerebralHelmToolDescriptor {
    let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // CoreModelTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // repository root
        .appendingPathComponent("packages/contracts/fixtures/valid/tools/descriptors", isDirectory: true)
    return try #require(try ToolDescriptorCatalog.loadDescriptors(directory: directory).first { $0.id == id })
}

@Test("the schema redactor redacts declared paths and preserves the rest (AC-34.2)")
func schemaRedactorRedactsDeclaredPaths() {
    let json = Data(#"{"hookId":"x","stdout":"secret-out","environment":{"TOKEN":"secret-env"},"exitCode":0}"#.utf8)
    let text = String(decoding: SchemaRedactor.redact(json, paths: ["/stdout", "/environment"]), as: UTF8.self)

    #expect(!text.contains("secret-out"))
    #expect(!text.contains("secret-env"))
    #expect(text.contains(SchemaRedactor.marker))
    #expect(text.contains("\"exitCode\":0")) // non-sensitive field preserved
    #expect(text.contains("hookId"))
}

@Test("a path that does not resolve leaves the document unchanged")
func redactorIgnoresMissingPaths() {
    let json = Data(#"{"hookId":"ondraft-dev"}"#.utf8)
    // hook.run's output paths do not exist in its input, so input is untouched.
    let text = String(decoding: SchemaRedactor.redact(json, paths: ["/stdout", "/environment", "/stderr"]), as: UTF8.self)
    #expect(text.contains("ondraft-dev"))
    #expect(!text.contains(SchemaRedactor.marker))
}

@Test("a secret in a note body is redacted in the tool-call record (AC-34.1, AC-34.2)")
func noteBodySecretIsRedacted() throws {
    let canary = "CANARY-body-9931"
    let input = Data("{\"title\":\"note\",\"body\":\"\(canary)\",\"kind\":\"idea\"}".utf8)
    let output = Data(#"{"noteId":"ch-idea-001","path":"inbox/ch-idea-001.md","created":true}"#.utf8)
    let result = ToolExecutionResult(toolID: "note.capture", status: .success, output: output, error: nil, durationMs: 3)

    let record = ToolCallRecorder.record(
        descriptor: try descriptor("note.capture"),
        input: input,
        result: result,
        startedAt: Date(timeIntervalSinceReferenceDate: 0),
        completedAt: Date(timeIntervalSinceReferenceDate: 0)
    )
    let text = String(decoding: try record.jsonData(), as: UTF8.self)

    #expect(!text.contains(canary))                 // AC-34.1
    #expect(text.contains(SchemaRedactor.marker))
    #expect(text.contains("ch-idea-001"))           // AC-34.2: useful output survives
    #expect(text.contains("note.capture"))
}

@Test("a secret in hook output is redacted in the tool-call record (AC-34.1)")
func hookOutputSecretIsRedacted() throws {
    let canary = "CANARY-out-4410"
    let input = Data(#"{"hookId":"ondraft-dev"}"#.utf8)
    let output = Data("{\"hookId\":\"ondraft-dev\",\"exitCode\":0,\"stdout\":\"\(canary)\",\"stderr\":\"\",\"timedOut\":false,\"durationMs\":1,\"environment\":{\"T\":\"\(canary)\"}}".utf8)
    let result = ToolExecutionResult(toolID: "hook.run", status: .success, output: output, error: nil, durationMs: 1)

    let record = ToolCallRecorder.record(
        descriptor: try descriptor("hook.run"),
        input: input,
        result: result,
        startedAt: Date(timeIntervalSinceReferenceDate: 0),
        completedAt: Date(timeIntervalSinceReferenceDate: 0)
    )
    let text = String(decoding: try record.jsonData(), as: UTF8.self)

    #expect(!text.contains(canary))                 // /stdout and /environment redacted
    #expect(text.contains("ondraft-dev"))           // hookId preserved
}

@Test("descriptor secret references are logical names, never values (AC-34.3)")
func secretReferencesAreLogicalNames() throws {
    let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("packages/contracts/fixtures/valid/tools/descriptors", isDirectory: true)

    for descriptor in try ToolDescriptorCatalog.loadDescriptors(directory: directory) {
        for reference in descriptor.secretReferences {
            #expect(reference.range(of: "^[a-z][a-z0-9_]*$", options: .regularExpression) != nil, "\(descriptor.id): \(reference)")
        }
    }
}
