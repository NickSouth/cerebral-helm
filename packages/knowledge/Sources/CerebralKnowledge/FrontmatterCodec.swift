import Foundation
import CerebralContracts
import CerebralShared

/// Minimal YAML-frontmatter codec for note files (FR-KNW-01).
///
/// Deliberately small and dependency-free (no Yams on the Windows toolchain): it
/// emits the flat, system-managed metadata block and parses it back to a string
/// map. The note body is everything after the closing `---`. User-added
/// frontmatter keys round-trip through the same map, so they are preserved.
public enum FrontmatterCodec {
    /// Renders `metadata` as a YAML frontmatter block followed by `body`.
    public static func emit(metadata: CerebralHelmNoteMetadata, body: String) -> String {
        var lines = ["---"]
        lines.append(field("schemaVersion", metadata.schemaVersion))
        lines.append(field("id", metadata.id))
        lines.append(field("title", metadata.title))
        lines.append(field("kind", metadata.kind))
        if let project = metadata.project { lines.append(field("project", project)) }
        lines.append(field("sensitivity", metadata.sensitivity.rawValue))
        lines.append(field("cloudPolicy", metadata.cloudPolicy.rawValue))
        lines.append(field("status", metadata.status.rawValue))
        lines.append(field("created", iso(metadata.created)))
        lines.append(field("updated", iso(metadata.updated)))
        if let reviewAfter = metadata.reviewAfter { lines.append(field("reviewAfter", iso(reviewAfter))) }
        lines.append("---")
        lines.append("")

        var content = lines.joined(separator: "\n") + "\n" + body
        if !content.hasSuffix("\n") { content += "\n" }
        return content
    }

    /// Splits a note into its frontmatter map and body. A file with no leading
    /// `---` block (or an unterminated one) yields an empty map and the whole
    /// content as the body.
    public static func parse(_ markdown: String) -> (frontmatter: [String: String], body: String) {
        let lines = markdown.components(separatedBy: "\n")
        guard lines.first == "---" else { return ([:], markdown) }

        var frontmatter: [String: String] = [:]
        var index = 1
        var closed = false
        while index < lines.count {
            let line = lines[index]
            index += 1
            if line == "---" { closed = true; break }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            let value = unquote(String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces))
            if !key.isEmpty { frontmatter[key] = value }
        }
        guard closed else { return ([:], markdown) }

        var body = lines[index...].joined(separator: "\n")
        if body.hasPrefix("\n") { body.removeFirst() }
        return (frontmatter, body)
    }

    // MARK: - Helpers

    private static func field(_ key: String, _ value: String) -> String {
        "\(key): \"\(escape(value))\""
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func unquote(_ value: String) -> String {
        guard value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") else { return value }
        return String(value.dropFirst().dropLast())
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }

    private static func iso(_ date: Date) -> String {
        ISO8601Timestamp.string(from: date)
    }
}
