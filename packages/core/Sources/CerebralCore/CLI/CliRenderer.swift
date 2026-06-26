import Foundation

/// Renders CLI results in human-readable and JSON forms so each surface speaks
/// the same data either way (FR-CMD-05, AC-26.2).
public enum CliRenderer {
    // MARK: Run outcome

    public static func human(_ outcome: RunOutcome) -> String {
        switch outcome {
        case let .executed(commandId, status, summary):
            return """
            Command \(commandId)
              status:  \(status.rawValue)
              summary: \(summary)
            """
        case let .rejected(reason, suggestions):
            guard !suggestions.isEmpty else { return reason }
            return reason + "\nSuggestions: " + suggestions.joined(separator: ", ")
        }
    }

    public static func json(_ outcome: RunOutcome) throws -> String {
        switch outcome {
        case let .executed(commandId, status, summary):
            return try encode(RunOutcomeJSON(
                outcome: "executed", commandId: commandId, status: status.rawValue,
                summary: summary, reason: nil, suggestions: nil
            ))
        case let .rejected(reason, suggestions):
            return try encode(RunOutcomeJSON(
                outcome: "rejected", commandId: nil, status: nil,
                summary: nil, reason: reason, suggestions: suggestions
            ))
        }
    }

    // MARK: Command status

    public static func human(_ record: CommandStatusRecord?, commandId: String) -> String {
        guard let record else { return "No record found for command \(commandId)." }
        return """
        Command \(record.commandId)
          status:  \(record.status.rawValue)
          message: \(record.message ?? "")
        """
    }

    public static func json(_ record: CommandStatusRecord?, commandId: String) throws -> String {
        try encode(StatusJSON(
            commandId: commandId, found: record != nil,
            status: record?.status.rawValue, message: record?.message
        ))
    }

    // MARK: Simulation preview

    public static func human(_ preview: SimulationPreview) -> String {
        var lines = [
            "Simulation: \(preview.id)",
            "  source:  \(preview.source)",
            "  mode:    \(preview.modeId)",
            "  summary: \(preview.summary)",
            "  steps:",
        ]
        for (index, step) in preview.steps.enumerated() {
            lines.append("    \(index + 1). \(step)")
        }
        return lines.joined(separator: "\n")
    }

    public static func json(_ preview: SimulationPreview) throws -> String {
        try encode(preview)
    }

    private static func encode<Value: Encodable>(_ value: Value) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }
}

private struct RunOutcomeJSON: Codable {
    let outcome: String
    let commandId: String?
    let status: String?
    let summary: String?
    let reason: String?
    let suggestions: [String]?
}

private struct StatusJSON: Codable {
    let commandId: String
    let found: Bool
    let status: String?
    let message: String?
}
