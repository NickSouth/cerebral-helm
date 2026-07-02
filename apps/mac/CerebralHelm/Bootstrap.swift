import Foundation
import CerebralCore
import CerebralStorage

/// The native shell's read-only startup pre-flight (FR-SHL-05, PRD §8.1).
///
/// Resolves data paths, then runs the canonical preflight
/// (`StartupValidation.validate`) over the bundled config, the operational
/// database, and the knowledge root. It returns a go/no-go decision and **never
/// writes**, so a failed pre-flight leaves user data untouched (AC-49.2/49.3); the
/// caller creates the writable state root only on `.ready`.
enum Bootstrap {
    /// The read-only recovery presentation, mirroring the bridge handshake
    /// `recovery` shape: a stable reason, a diagnostic code, and remediation
    /// (see `packages/contracts/schemas/bridge/handshake-response.schema.json`).
    struct Recovery: Equatable {
        let reason: String
        let diagnosticCode: String
        let remediation: String
        let details: [String]
    }

    enum Outcome {
        case ready(WorkspacePaths)
        case recovery(Recovery)
    }

    static func run() -> Outcome {
        guard let resources = Bundle.main.resourceURL else {
            return .recovery(Recovery(
                reason: "startup_validation_failed",
                diagnosticCode: "bundle_resources_missing",
                remediation: "Reinstall CerebralHelm; the application bundle is incomplete.",
                details: ["The app bundle Resources directory could not be located."]
            ))
        }

        let paths: WorkspacePaths
        do {
            paths = try WorkspacePaths.forApplication(bundleResourcesRoot: resources)
        } catch {
            return .recovery(Recovery(
                reason: "startup_validation_failed",
                diagnosticCode: "data_path_unresolved",
                remediation: "Check that ~/Library/Application Support is accessible, then relaunch.",
                details: ["Could not resolve data paths: \(error)"]
            ))
        }

        switch StartupValidation.validate(
            operationalDatabasePath: paths.operationalDatabasePath,
            knowledgeRoot: paths.knowledgeRoot,
            configDirectory: paths.configDirectory
        ) {
        case .ready:
            return .ready(paths)
        case let .recovery(diagnostics):
            let first = diagnostics.first
            return .recovery(Recovery(
                reason: "startup_validation_failed",
                diagnosticCode: first?.code ?? "startup_validation_failed",
                remediation: first?.guidance ?? "Restore from a verified backup, then relaunch.",
                details: diagnostics.map { "[\($0.code)] \($0.summary)" }
            ))
        }
    }
}
