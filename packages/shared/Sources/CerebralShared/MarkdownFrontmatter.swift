import Foundation

/// Minimal, parse-only YAML-frontmatter reader for Markdown descriptor files (NIC-129).
///
/// A deliberately small, dependency-free sibling of the knowledge module's `FrontmatterCodec`,
/// which `CerebralCore` cannot import — `CerebralKnowledge` is a *sibling* of `CerebralCore` (both
/// sit above it), not a dependency of it. `CerebralCore` does depend on `CerebralShared`, so the
/// parse half the Projects reader needs lives here.
///
/// ## Why this is not just `FrontmatterCodec` (NIC-116)
///
/// `FrontmatterCodec` moved to Yams so it can read real user-authored YAML. Sharing that
/// implementation would mean moving Yams down into `CerebralShared` — and *every* package depends
/// on Shared, so a C-backed YAML parser would land in Core, Tools, Storage, and Contracts to serve
/// the single integer key this file exists to read. `RepositoryBoundaryTests` enforces the
/// confinement (`only CerebralKnowledge imports the YAML parser`), mirroring the rule that keeps the
/// SQLite engine inside `CerebralStorage`.
///
/// The two readers are held in agreement by `FrontmatterParserConformanceTests`, which runs both
/// over the flat-scalar grammar they share.
///
/// ## What it supports
///
/// Only the flat `key: value` scalar shape `PROJECT.md` descriptors use — the frontmatter
/// CerebralHelm's own scaffolder and the shipped template write is exactly `importance: <int>`.
/// **Not supported, by design:** sequences (`- item`), nested mappings, block scalars (`|`, `>`),
/// comments, and multi-document streams. A descriptor needing any of those is not a descriptor;
/// note frontmatter is `FrontmatterCodec`'s job.
///
/// A document with no leading `---` block (or an unterminated one) yields an empty map and the whole
/// content as the body, so a descriptor without frontmatter reads as pure body, never an error.
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
