import Foundation
import ArgumentParser

/// The permanent `cerebral` developer and recovery CLI.
///
/// This harness drives the real portable core (command bus, parser, registry)
/// against repository config and fixture roots, so it runs on non-Mac systems
/// (FR-CMD-05, FR-CMD-06). NIC-26 part 1 ships the read surfaces; the action
/// surfaces (`mode`, `note`, `search`, `simulate`, `cancel`) follow.
@main
struct Cerebral: ParsableCommand {
    // `nonisolated(unsafe)` because swift-argument-parser 1.1.x predates
    // `Sendable` on `CommandConfiguration`; the value is effectively immutable.
    nonisolated(unsafe) static let configuration = CommandConfiguration(
        commandName: "cerebral",
        abstract: "CerebralHelm developer CLI.",
        subcommands: [Tools.self, Events.self]
    )
}

/// Options shared by every subcommand.
struct GlobalOptions: ParsableArguments {
    @Option(name: .long, help: "Repository root. Defaults to $CEREBRAL_ROOT or the current directory.")
    var root: String?

    @Flag(name: .long, help: "Emit machine-readable JSON instead of human-readable text.")
    var json = false
}

/// Resolves the repository root from an explicit flag, then `$CEREBRAL_ROOT`,
/// then the current working directory.
func resolveRepositoryRoot(_ explicit: String?) -> URL {
    if let explicit, !explicit.isEmpty {
        return URL(fileURLWithPath: explicit)
    }
    if let env = ProcessInfo.processInfo.environment["CEREBRAL_ROOT"], !env.isEmpty {
        return URL(fileURLWithPath: env)
    }
    return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
}
