import Foundation
import ArgumentParser
import CerebralCore
import CerebralStorage

/// `cerebral doctor` — read-only validation of data paths and schema (FR-SHL-05).
///
/// Reports whether storage is healthy or needs recovery, without writing anything
/// and without repairing or discarding any data. Exits non-zero in recovery so a
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
            print(options.json ? "{\"status\":\"ready\"}" : "Storage is healthy; writes may proceed.")
        case let .recovery(diagnostics):
            if options.json {
                let items = diagnostics
                    .map { "{\"store\":\"\($0.store)\",\"code\":\"\($0.code)\"}" }
                    .joined(separator: ",")
                print("{\"status\":\"recovery\",\"diagnostics\":[\(items)]}")
            } else {
                FileHandle.standardError.write(Data("Storage needs recovery (staying read-only):\n".utf8))
                for diagnostic in diagnostics {
                    print("- [\(diagnostic.code)] \(diagnostic.summary)\n  → \(diagnostic.guidance)")
                }
            }
            throw ExitCode(2)
        }
    }
}
