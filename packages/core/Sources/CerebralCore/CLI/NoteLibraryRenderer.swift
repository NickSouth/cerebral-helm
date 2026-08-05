import Foundation
import CerebralContracts

/// Renders the knowledge read surfaces — `note.list` and `note.read` — in
/// human-readable and machine-readable forms, so the CLI presents the same data
/// either way (FR-CMD-05, AC-26.2).
///
/// Both renderers work from the generated contract types, so what the CLI prints
/// is exactly what the tool returned: the JSON form is the tool output verbatim,
/// and the human form derives from the same fields rather than a parallel model
/// (NIC-162).
public enum NoteLibraryRenderer {
    // MARK: - note.list

    /// A fixed-column table, headed by the source root and note count.
    ///
    /// An empty knowledge root prints as an empty library at a named location —
    /// never as an error, and never as silence (FR-KNW-07).
    public static func humanReadable(list: CerebralHelmNoteListOutput) -> String {
        guard !list.notes.isEmpty else {
            return "No notes in \(list.root)."
        }

        let pathWidth = max(4, list.notes.map { $0.path.count }.max() ?? 4)
        let titleWidth = max(5, list.notes.map { $0.title.count }.max() ?? 5)

        // The count is the library's real size, not the number of rows below it: a
        // limited listing that counted its own rows would understate the library.
        var lines = [
            "\(list.total) \(list.total == 1 ? "note" : "notes") in \(list.root)",
            "",
            pad("PATH", pathWidth) + "  " + pad("TITLE", titleWidth) + "  UPDATED",
        ]
        for note in list.notes {
            lines.append(
                pad(note.path, pathWidth) + "  "
                    + pad(note.title, titleWidth) + "  "
                    // A note whose date is unreadable says so rather than
                    // borrowing a plausible one.
                    + (note.updated ?? "unknown")
            )
        }
        if list.truncated {
            lines.append("")
            lines.append("Showing \(list.notes.count) of \(list.total) — raise --limit to see more.")
        }
        return lines.joined(separator: "\n")
    }

    public static func json(list: CerebralHelmNoteListOutput) throws -> String {
        try encode(list)
    }

    // MARK: - note.read

    /// The note as it reads on disk: its source path, its frontmatter, then the
    /// Markdown body verbatim.
    public static func humanReadable(note: CerebralHelmNoteReadOutput) -> String {
        var lines = [
            note.title,
            // The full source location, so a reader can open the file itself —
            // the Markdown is the truth, this is only a view of it.
            "\(note.root)/\(note.path)",
        ]

        if !note.frontmatter.isEmpty {
            lines.append("")
            // Sorted so the same note always prints the same way.
            for key in note.frontmatter.keys.sorted() {
                lines.append("\(key): \(note.frontmatter[key] ?? "")")
            }
        }

        lines.append("")
        lines.append(note.body.hasSuffix("\n") ? String(note.body.dropLast()) : note.body)
        return lines.joined(separator: "\n")
    }

    public static func json(note: CerebralHelmNoteReadOutput) throws -> String {
        try encode(note)
    }

    // MARK: - Helpers

    private static func encode(_ value: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    private static func pad(_ value: String, _ width: Int) -> String {
        value.count >= width ? value : value + String(repeating: " ", count: width - value.count)
    }
}
