import Foundation
import ArgumentParser
import CerebralCore

/// `cerebral events …` — inspect the development event stream.
struct Events: ParsableCommand {
    nonisolated(unsafe) static let configuration = CommandConfiguration(
        abstract: "Inspect the event stream.",
        subcommands: [Tail.self]
    )

    /// `cerebral events tail` — print the most recent events.
    struct Tail: ParsableCommand {
        nonisolated(unsafe) static let configuration = CommandConfiguration(abstract: "Show the most recent events.")

        @OptionGroup var options: GlobalOptions

        @Option(name: .long, help: "Number of recent events to show.")
        var lines: Int = 20

        func run() throws {
            let root = resolveRepositoryRoot(options.root)
            let paths = try WorkspacePaths(repositoryRoot: root, environment: ProcessInfo.processInfo.environment)
            let entries = try EventLogReader.tail(paths.eventLogPath, lines: lines)

            guard !entries.isEmpty else {
                FileHandle.standardError.write(Data("No events recorded yet at \(paths.eventLogPath.path).\n".utf8))
                return
            }

            if options.json {
                // Each entry is already a JSON object, so joining yields a valid array.
                print("[" + entries.joined(separator: ",") + "]")
            } else {
                print(entries.joined(separator: "\n"))
            }
        }
    }
}
