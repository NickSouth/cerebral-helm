import Foundation
import CerebralContracts

/// Builds the structured, redacted record of one tool call (the `tool_calls`
/// row, FR-OBS-01/03).
///
/// Input and output are redacted with the descriptor's declared
/// `logging.redactionPaths` before they enter the record, so a secret in a hook
/// environment or a note body never reaches the operational log, a fixture, or a
/// diagnostic export (AC-34.1). Non-sensitive fields survive (AC-34.2).
public enum ToolCallRecorder {
    public static let adapterIDPreMacMock = "mock_native"

    public static func record(
        descriptor: CerebralHelmToolDescriptor,
        input: Data,
        result: ToolExecutionResult,
        startedAt: Date,
        completedAt: Date,
        adapterID: String = ToolCallRecorder.adapterIDPreMacMock
    ) -> CerebralHelmToolResult {
        let paths = descriptor.logging.redactionPaths
        let error = result.error.map {
            CerebralHelmToolResultError(category: $0.category, code: $0.code, details: $0.details, message: $0.message, remediation: $0.remediation)
        }

        return CerebralHelmToolResult(
            adapterID: adapterID,
            completedAt: completedAt,
            durationMS: result.durationMs,
            error: error,
            redactedInput: object(from: SchemaRedactor.redact(input, paths: paths)),
            redactedOutput: object(from: SchemaRedactor.redact(result.output ?? Data("{}".utf8), paths: paths)),
            schemaVersion: "1.0.0",
            startedAt: startedAt,
            status: result.status,
            toolID: descriptor.id,
            toolVersion: descriptor.version
        )
    }

    private static func object(from data: Data) -> [String: JSONAny] {
        (try? JSONDecoder().decode([String: JSONAny].self, from: data)) ?? [:]
    }
}
