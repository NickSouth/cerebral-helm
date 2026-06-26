import Foundation
import ArgumentParser
import CerebralCore

/// `cerebral command …` — inspect submitted commands.
struct Command: ParsableCommand {
    nonisolated(unsafe) static let configuration = CommandConfiguration(
        commandName: "command",
        abstract: "Inspect submitted commands.",
        subcommands: [Status.self]
    )

    /// `cerebral command status <id>` — show a command's latest status from the
    /// persisted event log.
    struct Status: ParsableCommand {
        nonisolated(unsafe) static let configuration = CommandConfiguration(abstract: "Show a command's status.")

        @OptionGroup var options: GlobalOptions

        @Argument(help: "Command id.")
        var id: String

        func run() throws {
            let paths = try workspacePaths(options)
            let record = try CommandStatusReader.latest(commandId: id, eventLogPath: paths.eventLogPath)
            print(options.json
                ? try CliRenderer.json(record, commandId: id)
                : CliRenderer.human(record, commandId: id))
        }
    }
}

/// `cerebral cancel <id>` — cancel a command.
///
/// The CLI is stateless across invocations, so this reports the command's
/// persisted terminal state idempotently. Cancelling a still-running command
/// from a separate session needs a persistent runtime, which arrives with the
/// operational database.
struct Cancel: ParsableCommand {
    nonisolated(unsafe) static let configuration = CommandConfiguration(abstract: "Cancel a command (idempotent).")

    @OptionGroup var options: GlobalOptions

    @Argument(help: "Command id.")
    var id: String

    func run() throws {
        let paths = try workspacePaths(options)
        let record = try CommandStatusReader.latest(commandId: id, eventLogPath: paths.eventLogPath)

        if options.json {
            print(try CliRenderer.json(record, commandId: id))
            return
        }

        guard let record else {
            print("No command \(id) found.")
            return
        }
        switch record.status {
        case .succeeded, .failed, .cancelled:
            print("Command \(id) is already \(record.status.rawValue); nothing to cancel.")
        default:
            print("Command \(id) is \(record.status.rawValue); the CLI cannot cancel a command from a separate session yet.")
        }
    }
}
