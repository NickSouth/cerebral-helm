import Foundation

/// Minimal, parse-only YAML-frontmatter reader for Markdown descriptor files (NIC-129).
///
/// A deliberately small, dependency-free sibling of the knowledge module's
/// `FrontmatterCodec`, which `CerebralCore` cannot import — `CerebralKnowledge` is a
/// *sibling* of `CerebralCore` (both sit above it), not a dependency of it. `CerebralCore`
/// does depend on `CerebralShared`, so the parse half the Projects reader needs lives here.
///
/// It splits a Markdown document into its leading `---` frontmatter block, parsed to a flat
/// `key: value` map, and the body that follows. It parses only the flat scalar shape the
/// `PROJECT.md` project descriptors use — no nested YAML, sequences, or block scalars. A
/// document with no leading `---` block (or an unterminated one) yields an empty map and the
/// whole content as the body, so a descriptor without frontmatter reads as pure body, never
/// an error.
public enum MarkdownFrontmatter {
    /// Splits `markdown` into its frontmatter map and body. Values wrapped in matching
    /// double quotes are unquoted; lines without a colon (e.g. YAML comments) are skipped.
    /// The body is everything after the closing `---`, with a single leading newline trimmed.
    public static func parse(
        _ markdown: String
    ) -> (frontmatter: [String: String], body: String) {
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
            let value = unquote(
                String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            )
            if !key.isEmpty { frontmatter[key] = value }
        }
        // An unterminated block is not frontmatter: return the whole document as body.
        guard closed else { return ([:], markdown) }

        var body = lines[index...].joined(separator: "\n")
        if body.hasPrefix("\n") { body.removeFirst() }
        return (frontmatter, body)
    }

    private static func unquote(_ value: String) -> String {
        guard value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") else { return value }
        return String(value.dropFirst().dropLast())
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }
}
