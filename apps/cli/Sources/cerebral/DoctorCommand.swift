import Foundation
import ArgumentParser
import CerebralCore
import CerebralStorage

/// `cerebral doctor` — read-only validation of data paths and schema (FR-SHL-05).
///
/// Reports which environment resolved and where its durable roots landed, then
/// whether storage is healthy or needs recovery, without writing anything and
/// without repairing or discarding any data. Exits non-zero in recovery so a
/// script can detect it.
struct Doctor: ParsableCommand {
    nonisolated(unsafe) static let configuration = CommandConfiguration(
        abstract: "Validate data paths and schema (read-only)."
    )

    @OptionGroup var options: GlobalOptions

    func run() throws {
        let paths = try workspacePaths(options)
        let check = StartupValidation.validate(
            operationalDatabasePath: paths.operationalDatabasePath,
            knowledgeRoot: paths.knowledgeRoot
        )

        switch check {
        case .ready:
            if options.json {
                print(try DoctorReport.json(paths: paths, status: "ready", diagnostics: []))
            } else {
                print(DoctorReport.roots(paths))
                print("Storage is healthy; writes may proceed.")
            }
        case let .recovery(diagnostics):
            if options.json {
                print(try DoctorReport.json(paths: paths, status: "recovery", diagnostics: diagnostics))
            } else {
                print(DoctorReport.roots(paths))
                // Flush before crossing to stderr: stdout is block-buffered while
                // stderr is not, so without this the banner overtakes the roots
                // block whenever both are pointed at the same terminal.
                //
                // `nil` flushes every open output stream rather than naming `stdout`.
                // On Glibc `stdout` is a mutable global, which Swift 6 strict
                // concurrency rejects as shared mutable state — Darwin accepts it, so
                // naming it compiles on macOS and breaks the Linux build.
                fflush(nil)
                FileHandle.standardError.write(Data("Storage needs recovery (staying read-only):\n".utf8))
                for diagnostic in diagnostics {
                    print("- [\(diagnostic.code)] \(diagnostic.summary)\n  → \(diagnostic.guidance)")
                }
            }
            throw ExitCode(2)
        }
    }
}

/// Renders `doctor`'s read-only view: the resolved environment and its durable
/// roots, plus the storage verdict (FR-CFG-06).
///
/// **Why the roots print in both outcomes.** A ``RecoveryDiagnostic`` names a
/// *store* (`knowledge`, `operational_sqlite`) but never a path, so on its own it
/// cannot tell you which environment's data failed — a broken development root and
/// a broken personal-production root produce identical output. Printing the roots
/// alongside the verdict is what makes the recovery guidance actionable.
///
/// **Knowledge root caveat.** This reports the root the *environment* resolved.
/// A user who re-points the knowledge root through settings (NIC-138) is served by
/// `EffectiveSettings.knowledgeRootURL`, which reads the operational database — and
/// `doctor` deliberately never opens that database, because doing so would create
/// and migrate it, breaking the read-only guarantee this command exists to provide.
enum DoctorReport {
    private struct View: Codable {
        struct Roots: Codable {
            let repository: String
            let state: String
            let config: String
            let database: String
            let knowledge: String
            let backups: String
            let eventLog: String
        }

        struct Diagnostic: Codable {
            let store: String
            let code: String
        }

        let environment: String
        let roots: Roots
        let status: String
        let diagnostics: [Diagnostic]
    }

    private static func view(
        _ paths: WorkspacePaths, _ status: String, _ diagnostics: [RecoveryDiagnostic]
    ) -> View {
        View(
            environment: paths.environment.rawValue,
            roots: View.Roots(
                repository: paths.repositoryRoot.path,
                state: paths.stateRoot.path,
                config: paths.configDirectory.path,
                database: paths.operationalDatabasePath.path,
                knowledge: paths.knowledgeRoot.path,
                backups: paths.backupsDirectory.path,
                eventLog: paths.eventLogPath.path
            ),
            status: status,
            diagnostics: diagnostics.map { View.Diagnostic(store: $0.store, code: $0.code) }
        )
    }

    static func json(
        paths: WorkspacePaths, status: String, diagnostics: [RecoveryDiagnostic]
    ) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(view(paths, status, diagnostics)), as: UTF8.self)
    }

    /// The human-readable roots block. Paths are emitted verbatim rather than
    /// abbreviated against `~`, so what is printed is exactly what can be copied
    /// into a shell or a backup command.
    static func roots(_ paths: WorkspacePaths) -> String {
        let rows: [(String, URL)] = [
            ("Repository", paths.repositoryRoot),
            ("State root", paths.stateRoot),
            ("Config", paths.configDirectory),
            ("Database", paths.operationalDatabasePath),
            ("Knowledge", paths.knowledgeRoot),
            ("Backups", paths.backupsDirectory),
            ("Event log", paths.eventLogPath)
        ]
        let width = rows.map(\.0.count).max() ?? 0
        let body = rows
            .map { "  \($0.0.padding(toLength: width, withPad: " ", startingAt: 0))  \($0.1.path)" }
            .joined(separator: "\n")
        return "Environment: \(paths.environment.rawValue)\n\(body)\n"
    }
}
