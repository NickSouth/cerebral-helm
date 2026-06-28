import Foundation
import ArgumentParser

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
            let entries = try recentEventPayloads(options: options, limit: lines)

            guard !entries.isEmpty else {
                FileHandle.standardError.write(Data("No events recorded yet.\n".utf8))
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
