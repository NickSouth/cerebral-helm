import Foundation
import Yams
import CerebralContracts
import CerebralShared

/// YAML-frontmatter codec for note files (FR-KNW-01).
///
/// **Deliberately asymmetric (NIC-116): Yams reads, the hand-rolled emitter writes.**
///
/// Reading needs real YAML. Notes are authored in Obsidian as often as by CerebralHelm, and the
/// previous line-splitting parser required a colon per line — so an ordinary tag list
///
/// ```yaml
/// tags:
///   - work
///   - urgent
/// ```
///
/// parsed `tags` to the empty string and silently dropped both values. Multiline scalars, quoted
/// colons, and nested mappings were mangled the same way.
///
/// Writing stays on ``emit(metadata:body:)``. Yams cannot reproduce an existing file byte-for-byte:
/// it re-indents block sequences under a mapping key (`  - a` → `- a`, not configurable via the
/// emitter's `indent:`) and re-quotes scalars it would otherwise re-resolve. Adopting it on the
/// write side would rewrite every note in the user's vault on first touch — durable state churned to
/// satisfy a parser swap. The asymmetry costs nothing, because **nothing here ever rewrites an
/// existing note's frontmatter**: `emit` has exactly one caller, note *capture*.
///
/// Not to be confused with `CerebralShared.MarkdownFrontmatter`, the narrow reader `CerebralCore`
/// uses for `PROJECT.md` descriptors. That one stays dependency-free on purpose, so Yams does not
/// enter every package's dependency graph; the two are held in agreement on the flat-scalar grammar
/// they share by `FrontmatterParserConformanceTests`.
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
    ///
    /// Malformed YAML inside a well-formed block degrades the same way: an empty map and the body
    /// that follows, never a thrown error. A note the user is midway through editing must still be
    /// readable and indexable — its body is the valuable part.
    public static func parse(_ markdown: String) -> (frontmatter: [String: String], body: String) {
        guard let block = splitBlock(markdown) else { return ([:], markdown) }
        return (parseFrontmatter(block.yaml), block.body)
    }

    /// Locate the leading `---` … `---` block, returning its YAML source and the body after it.
    /// `nil` when there is no block, or it never closes — in both cases the whole document is body.
    private static func splitBlock(_ markdown: String) -> (yaml: String, body: String)? {
        let lines = markdown.components(separatedBy: "\n")
        guard lines.first == "---" else { return nil }

        var index = 1
        var yamlLines: [String] = []
        var closed = false
        while index < lines.count {
            let line = lines[index]
            index += 1
            if line == "---" { closed = true; break }
            yamlLines.append(line)
        }
        guard closed else { return nil }

        var body = lines[index...].joined(separator: "\n")
        if body.hasPrefix("\n") { body.removeFirst() }
        return (yamlLines.joined(separator: "\n"), body)
    }

    /// Parse the block's YAML into the flat `[String: String]` map callers expect.
    ///
    /// Uses `Yams.compose` (the node tree) rather than `Yams.load` (typed Swift values) on purpose.
    /// `load` applies YAML's implicit resolution, which **coerces** scalars before we can see them:
    /// `2026-08-05` becomes a `Date`, `007` becomes the integer `7`, `no` becomes `false`. Every one
    /// of those loses the author's literal text on the way into a `String` map. The node tree
    /// carries each scalar's source text verbatim, so what the user typed is what callers read —
    /// and it sidesteps the whole family of resolver quirks rather than disabling them one by one.
    private static func parseFrontmatter(_ yaml: String) -> [String: String] {
        guard
            let node = try? Yams.compose(yaml: yaml),
            let mapping = node.mapping
        else {
            // Malformed YAML, or a block that is not a mapping (a bare list or scalar). Neither is
            // frontmatter; the body is still returned by the caller.
            return [:]
        }

        var frontmatter: [String: String] = [:]
        for (keyNode, valueNode) in mapping {
            guard let key = keyNode.scalar?.string, !key.isEmpty else { continue }
            flatten(valueNode, into: &frontmatter, at: key)
        }
        return frontmatter
    }

    /// Flatten one YAML value into the string map under `key`.
    ///
    /// The map is flat and stringly-typed, so richer YAML has to be projected into it. The rules,
    /// chosen so nothing is invented and nothing common is lost:
    ///
    /// - **Scalar** → its literal source text. A null (`key:` with no value) reads as `""`, matching
    ///   what the previous parser produced for an empty value.
    /// - **Sequence** → elements joined with `", "`, which is how a tag list reads naturally and
    ///   what the old parser was silently dropping entirely.
    /// - **Mapping** → flattened recursively under dotted keys (`author.name`), so nested metadata
    ///   is reachable instead of discarded.
    ///
    /// Nested containers inside a sequence (a list of mappings) collapse to their joined scalars —
    /// the one shape a flat map genuinely cannot represent. That is rare in note frontmatter and
    /// degrading it beats either dropping the key or inventing a serialization for it.
    ///
    /// A YAML **alias** (`*anchor`) is omitted rather than guessed at: resolving it means walking
    /// back to its anchor, and a wrong resolution would put text in a note's metadata that the
    /// author never wrote. Anchors do not occur in note frontmatter in practice.
    private static func flatten(_ node: Node, into map: inout [String: String], at key: String) {
        switch node {
        case let .scalar(scalar):
            map[key] = scalar.string
        case let .sequence(sequence):
            map[key] = sequence.compactMap(scalarText).joined(separator: ", ")
        case let .mapping(mapping):
            for (childKey, childValue) in mapping {
                guard let name = childKey.scalar?.string, !name.isEmpty else { continue }
                flatten(childValue, into: &map, at: "\(key).\(name)")
            }
        case .alias:
            break
        }
    }

    /// A sequence element as text: its literal scalar, or its nested scalars joined. `nil` for an
    /// alias, so it drops out of the join rather than contributing an empty element.
    private static func scalarText(_ node: Node) -> String? {
        switch node {
        case let .scalar(scalar):
            return scalar.string
        case let .sequence(sequence):
            return sequence.compactMap(scalarText).joined(separator: ", ")
        case let .mapping(mapping):
            return mapping.compactMap { scalarText($0.value) }.joined(separator: ", ")
        case .alias:
            return nil
        }
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

    // `unquote` is gone with the line-splitting parser (NIC-116): Yams handles quoting, escapes,
    // and every other scalar style, so there is nothing left to strip by hand.

    private static func iso(_ date: Date) -> String {
        ISO8601Timestamp.string(from: date)
    }
}
