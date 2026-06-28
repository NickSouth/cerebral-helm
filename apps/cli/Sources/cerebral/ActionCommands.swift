import Foundation
import ArgumentParser
import CerebralCore

/// `cerebral open <id>` — open a configured application or URL reference.
struct Open: AsyncParsableCommand {
    nonisolated(unsafe) static let configuration = CommandConfiguration(abstract: "Open a configured app or URL.")

    @OptionGroup var options: GlobalOptions

    @Argument(help: "App or URL reference id, e.g. vscode or github.")
    var id: String

    func run() async throws {
        try await runThroughRuntime("open \(id)", options: options)
    }
}

/// `cerebral hook <id>` — run a configured allowlisted hook (requires confirmation).
struct Hook: AsyncParsableCommand {
    nonisolated(unsafe) static let configuration = CommandConfiguration(abstract: "Run a configured hook.")

    @OptionGroup var options: GlobalOptions

    @Argument(help: "Hook id, e.g. ondraft-dev.")
    var id: String

    func run() async throws {
        try await runThroughRuntime("hook \(id)", options: options)
    }
}

/// `cerebral mode [id]` — apply a configured mode, or show the active mode when
/// no id is given.
struct Mode: AsyncParsableCommand {
    nonisolated(unsafe) static let configuration = CommandConfiguration(abstract: "Apply a configured mode, or show the active mode.")

    @OptionGroup var options: GlobalOptions

    @Argument(help: "Mode id to apply, e.g. developer. Omit to show the active mode.")
    var id: String?

    func run() async throws {
        guard let id else {
            try renderActiveMode(options: options)
            return
        }
        let outcome = try await runThroughRuntime("mode \(id)", options: options)
        try recordModeSessionIfApplied(modeID: id, outcome: outcome, options: options)
    }
}

/// `cerebral note <text…>` — capture a note.
struct Note: AsyncParsableCommand {
    nonisolated(unsafe) static let configuration = CommandConfiguration(abstract: "Capture a note.")

    @OptionGroup var options: GlobalOptions

    @Argument(parsing: .remaining, help: "Note text.")
    var words: [String] = []

    func run() async throws {
        try await runThroughRuntime("note \(words.joined(separator: " "))", options: options)
    }
}

/// `cerebral search <text…>` — search notes.
struct Search: AsyncParsableCommand {
    nonisolated(unsafe) static let configuration = CommandConfiguration(abstract: "Search notes.")

    @OptionGroup var options: GlobalOptions

    @Argument(parsing: .remaining, help: "Search query.")
    var words: [String] = []

    func run() async throws {
        try await runThroughRuntime("search \(words.joined(separator: " "))", options: options)
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
