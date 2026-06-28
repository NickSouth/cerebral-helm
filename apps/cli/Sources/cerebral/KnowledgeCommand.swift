import Foundation
import ArgumentParser
import CerebralKnowledge

/// `cerebral knowledge …` — inspect and maintain the knowledge base.
struct Knowledge: ParsableCommand {
    nonisolated(unsafe) static let configuration = CommandConfiguration(
        commandName: "knowledge",
        abstract: "Inspect and maintain the knowledge base.",
        subcommands: [Rebuild.self]
    )

    /// `cerebral knowledge rebuild` — drop and reconstruct the search index from
    /// the Markdown files (FR-KNW-06). The files are the source of truth, so this
    /// is always safe; deleting the index and rebuilding preserves results.
    struct Rebuild: ParsableCommand {
        nonisolated(unsafe) static let configuration = CommandConfiguration(
            abstract: "Rebuild the search index from the Markdown notes."
        )

        @OptionGroup var options: GlobalOptions

        func run() throws {
            let paths = try workspacePaths(options)
            try makeKnowledgeService(paths).rebuild()
            if options.json {
                print("{\"rebuilt\":true}")
            } else {
                print("Rebuilt the search index from \(paths.knowledgeRoot.path).")
            }
        }
    }
}
