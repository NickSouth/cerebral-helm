import Foundation
import ArgumentParser
import CerebralCore

/// `cerebral mode <id>` — apply a configured mode through the command bus.
struct Mode: ParsableCommand {
    nonisolated(unsafe) static let configuration = CommandConfiguration(abstract: "Apply a configured mode.")

    @OptionGroup var options: GlobalOptions

    @Argument(help: "Mode id, e.g. developer.")
    var id: String

    func run() throws {
        let outcome = try makeSession(options).run("mode \(id)", source: .cli)
        try emit(outcome, json: options.json)
    }
}

/// `cerebral note <text…>` — capture a note through the command bus.
struct Note: ParsableCommand {
    nonisolated(unsafe) static let configuration = CommandConfiguration(abstract: "Capture a note.")

    @OptionGroup var options: GlobalOptions

    @Argument(parsing: .remaining, help: "Note text.")
    var words: [String] = []

    func run() throws {
        let outcome = try makeSession(options).run("note \(words.joined(separator: " "))", source: .cli)
        try emit(outcome, json: options.json)
    }
}

/// `cerebral search <text…>` — search notes through the command bus.
struct Search: ParsableCommand {
    nonisolated(unsafe) static let configuration = CommandConfiguration(abstract: "Search notes.")

    @OptionGroup var options: GlobalOptions

    @Argument(parsing: .remaining, help: "Search query.")
    var words: [String] = []

    func run() throws {
        let outcome = try makeSession(options).run("search \(words.joined(separator: " "))", source: .cli)
        try emit(outcome, json: options.json)
    }
}

/// `cerebral simulate [fixture]` — render a deterministic plan preview without
/// executing anything.
struct Simulate: ParsableCommand {
    nonisolated(unsafe) static let configuration = CommandConfiguration(abstract: "Preview a simulation fixture.")

    @OptionGroup var options: GlobalOptions

    @Argument(help: "Simulation fixture id.")
    var fixture: String = "successful-developer-mode"

    func run() throws {
        let paths = try workspacePaths(options)
        let preview = try SimulationPreviewLoader.load(id: fixture, fixturesDirectory: paths.fixturesDirectory)
        print(options.json ? try CliRenderer.json(preview) : CliRenderer.human(preview))
    }
}
