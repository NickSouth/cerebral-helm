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

    /// Returns `markdown` with frontmatter `key` set to `value`, preserving every other byte.
    ///
    /// The write counterpart of ``parse(_:)``, kept in the same type so the two cannot drift: a
    /// value this writes must be a value that reader reads back. Three cases, matching what a
    /// hand-authored descriptor can actually look like —
    ///
    /// - the key exists: its line is replaced, and no other line moves;
    /// - the block exists without the key: the line is inserted directly after the opening fence;
    /// - there is no block, or an unterminated one: a real block is prepended and the original
    ///   content is kept intact below it (an unterminated fence is not frontmatter, so it is body).
    ///
    /// `value` is written verbatim — the caller owns any quoting, because only the caller knows
    /// whether its value needs it. Use ``scalar(_:)`` to serialize an arbitrary string safely.
    public static func setting(
        _ markdown: String, key: String, value: String
    ) -> String {
        let line = "\(key): \(value)"
        let lines = markdown.components(separatedBy: "\n")

        // No frontmatter block: prepend a real one and keep the body untouched.
        guard lines.first == "---" else {
            return "---\n\(line)\n---\n\n" + markdown
        }

        var closeIndex: Int?
        var keyIndex: Int?
        var index = 1
        while index < lines.count {
            if lines[index] == "---" { closeIndex = index; break }
            if keyIndex == nil, let colon = lines[index].firstIndex(of: ":") {
                let existing = String(lines[index][..<colon]).trimmingCharacters(in: .whitespaces)
                if existing == key { keyIndex = index }
            }
            index += 1
        }

        // An unterminated block is not a real block — prepend one rather than editing inside it.
        guard closeIndex != nil else {
            return "---\n\(line)\n---\n\n" + markdown
        }

        var updated = lines
        if let keyIndex {
            updated[keyIndex] = line
        } else {
            updated.insert(line, at: 1)
        }
        return updated.joined(separator: "\n")
    }

    /// Serializes `value` as a frontmatter scalar, quoting only when it has to.
    ///
    /// Unquoted is preferred because a descriptor is a file the user reads and edits, and
    /// `linear_project: CerebralHelm` is plainly nicer than the quoted form. Quoting kicks in only
    /// where the grammar in ``parse(_:)`` would otherwise read something different back:
    ///
    /// - a value already wrapped in double quotes would be **unquoted** on read, losing them;
    /// - a value containing a newline would end the line, and possibly the block.
    ///
    /// A value containing an inner colon needs no quoting: the parser splits on the FIRST colon,
    /// so everything after it is the value.
    public static func scalar(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasNewline = trimmed.contains("\n") || trimmed.contains("\r")
        let looksQuoted = trimmed.count >= 2 && trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"")
        guard hasNewline || looksQuoted else { return trimmed }
        let escaped = trimmed
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        return "\"\(escaped)\""
    }

    private static func unquote(_ value: String) -> String {
        guard value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") else { return value }
        return String(value.dropFirst().dropLast())
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }
}
