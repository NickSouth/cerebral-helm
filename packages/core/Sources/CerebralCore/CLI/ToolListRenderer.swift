import Foundation

/// Renders a configured-tool list in human-readable and machine-readable forms,
/// so the CLI presents the same data either way (FR-CMD-05, AC-26.2).
public enum ToolListRenderer {
    /// A fixed-column human-readable table.
    public static func humanReadable(_ tools: [ConfiguredTool]) -> String {
        guard !tools.isEmpty else {
            return "No tools are configured."
        }
        let idWidth = max(4, tools.map { $0.id.count }.max() ?? 4)
        let riskWidth = max(4, tools.map { $0.risk.count }.max() ?? 4)

        var lines = [
            pad("TOOL", idWidth) + "  " + pad("RISK", riskWidth) + "  TIMEOUT  PRE-MAC",
        ]
        for tool in tools {
            let availability = tool.availableInPreMac ? "yes" : "no"
            lines.append(
                pad(tool.id, idWidth) + "  "
                    + pad(tool.risk, riskWidth) + "  "
                    + pad("\(tool.timeoutMs)ms", 7) + "  "
                    + availability
            )
        }
        return lines.joined(separator: "\n")
    }

    /// A pretty-printed JSON array with stable key ordering.
    public static func json(_ tools: [ConfiguredTool]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        let data = try encoder.encode(tools)
        return String(decoding: data, as: UTF8.self)
    }

    private static func pad(_ value: String, _ width: Int) -> String {
        value.count >= width ? value : value + String(repeating: " ", count: width - value.count)
    }
}
