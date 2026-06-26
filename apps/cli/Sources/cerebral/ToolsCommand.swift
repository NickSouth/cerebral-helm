import Foundation
import ArgumentParser
import CerebralCore

/// `cerebral tools …` — inspect the configured tool registry.
struct Tools: ParsableCommand {
    nonisolated(unsafe) static let configuration = CommandConfiguration(
        abstract: "Inspect the configured tools.",
        subcommands: [List.self]
    )

    /// `cerebral tools list` — list configured tools and their risk/availability.
    struct List: ParsableCommand {
        nonisolated(unsafe) static let configuration = CommandConfiguration(abstract: "List configured tools.")

        @OptionGroup var options: GlobalOptions

        func run() throws {
            let root = resolveRepositoryRoot(options.root)
            let paths = try WorkspacePaths(repositoryRoot: root, environment: ProcessInfo.processInfo.environment)
            let registry = try ConfiguredToolRegistry.load(configDirectory: paths.configDirectory)

            if options.json {
                print(try ToolListRenderer.json(registry.tools))
            } else {
                print(ToolListRenderer.humanReadable(registry.tools))
            }
        }
    }
}
