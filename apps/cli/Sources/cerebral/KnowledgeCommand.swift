import Foundation
import ArgumentParser
import CerebralContracts
import CerebralCore
import CerebralKnowledge
import CerebralRuntimeHost

/// `cerebral knowledge …` — inspect and maintain the knowledge base.
///
/// The read subcommands (`list`, `read`) go through the command bus rather than
/// calling the knowledge service directly, so they run the same policy and leave
/// the same redacted audit trail as any other tool call (NIC-162). `rebuild` is
/// the exception: it maintains derived state and is not a tool.
struct Knowledge: ParsableCommand {
    nonisolated(unsafe) static let configuration = CommandConfiguration(
        commandName: "knowledge",
        abstract: "Inspect and maintain the knowledge base.",
        subcommands: [List.self, Read.self, Rebuild.self]
    )

    /// `cerebral knowledge list` — the notes on disk, most recently changed
    /// first. Reads the Markdown itself, so a note written in another editor is
    /// listed without waiting for a rebuild.
    struct List: AsyncParsableCommand {
        nonisolated(unsafe) static let configuration = CommandConfiguration(
            abstract: "List the notes in the knowledge root."
        )

        @OptionGroup var options: GlobalOptions

        @Option(name: .long, help: "Show only the most recently changed <n> notes.")
        var limit: Int?

        func run() async throws {
            let input = limit.map { "notes-list \($0)" } ?? "notes-list"
            let output = try CerebralHelmNoteListOutput(data: try await toolOutput(input, options: options))
            print(
                options.json
                    ? try NoteLibraryRenderer.json(list: output)
                    : NoteLibraryRenderer.humanReadable(list: output)
            )
        }
    }

    /// `cerebral knowledge read <path>` — one note's frontmatter and body. The
    /// path is the one `list` reports; anything resolving outside the knowledge
    /// root is refused by the service, not read.
    struct Read: AsyncParsableCommand {
        nonisolated(unsafe) static let configuration = CommandConfiguration(
            abstract: "Read one note by its path relative to the knowledge root."
        )

        @OptionGroup var options: GlobalOptions

        // Paths carry spaces — a note authored elsewhere is titled by its
        // filename — so the whole remainder is the path. Qualified because
        // CerebralContracts also declares an `Argument` (the disclosure's).
        @ArgumentParser.Argument(parsing: .remaining, help: "Note path relative to the knowledge root, e.g. inbox/idea.md.")
        var words: [String] = []

        func run() async throws {
            let path = words.joined(separator: " ")
            guard !path.isEmpty else {
                throw ValidationError("A note path is required, e.g. cerebral knowledge read inbox/idea.md")
            }
            let output = try CerebralHelmNoteReadOutput(
                data: try await toolOutput("notes-read \(path)", options: options)
            )
            print(
                options.json
                    ? try NoteLibraryRenderer.json(note: output)
                    : NoteLibraryRenderer.humanReadable(note: output)
            )
        }
    }

    /// `cerebral knowledge rebuild` — drop and reconstruct the search index from
    /// the Markdown files (FR-KNW-06). The files are the source of truth, so this
    /// is always safe; deleting the index and rebuilding preserves results.
    struct Rebuild: ParsableCommand {
        nonisolated(unsafe) static let configuration = CommandConfiguration(
            abstract: "Rebuild the search index from the Markdown notes."
        )

        @OptionGroup var options: GlobalOptions

        func run() throws {
            let knowledge = try makeKnowledgeService(try workspacePaths(options))
            let indexed = try knowledge.rebuild()
            // Report the EFFECTIVE root and what the rebuild covered — a re-pointed
            // root (NIC-138) is the one that was read, so naming the default would
            // be wrong, and a bare "rebuilt" hides an empty index.
            if options.json {
                print("{\"rebuilt\":true,\"root\":\"\(knowledge.rootPath)\",\"noteCount\":\(indexed)}")
            } else {
                let notes = indexed == 1 ? "1 note" : "\(indexed) notes"
                print("Rebuilt the search index from \(knowledge.rootPath) — \(notes) indexed.")
            }
        }
    }
}
