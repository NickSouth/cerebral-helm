import Foundation
import CerebralContracts

/// The validated config-write path for the user-overrides layer (FR-CFG-04).
///
/// A programmatic edit (settings UI, quick-app pinning) writes a per-mode
/// override file exactly as a manual edit would, then validates it through the
/// same ``ConfigLoader`` that validates manual edits — the two paths cannot
/// diverge because they are one path. A candidate that fails validation is
/// rolled back on disk and the last-known-good configuration stays active
/// (FR-CFG-02); a write is never reported applied unless the full layered load
/// activated it.
///
/// Overrides carry only the schema's allowlisted per-mode fields (bundle-id
/// style config ids, never paths or executables), so this path can tailor a
/// mode but can never weaken risk or confirmation policy (ADR-003).
public struct ConfigOverrideWriter {
    private let workspace: WorkspacePaths
    private let loader: ConfigLoader

    public init(workspace: WorkspacePaths) {
        self.workspace = workspace
        self.loader = ConfigLoader(workspace: workspace)
    }

    /// The outcome of a write: the activated configuration, or the validation
    /// errors that rejected it (with the file system rolled back).
    public enum Outcome {
        case applied(ActiveConfig)
        case rejected(errors: [CerebralHelmConfigValidationError])
    }

    /// Creates or replaces the override for `override.id` at its canonical path
    /// (`overrides/<modeID>.json`). Document validation runs before anything
    /// touches disk; the layered load validates the merged result after.
    public func write(_ override: CerebralHelmModeOverride) -> Outcome {
        let fileLabel = "overrides/\(override.id).json"
        guard let data = try? override.jsonData() else {
            return .rejected(errors: [makeError(
                file: fileLabel, field: "/",
                expected: "an encodable override document",
                message: "Override could not be encoded.",
                remediation: "Report this as an internal error."
            )])
        }
        let documentErrors = ConfigValidator.overrideDocumentErrors(file: fileLabel, data: data)
        guard documentErrors.isEmpty else {
            return .rejected(errors: documentErrors)
        }

        let target = overrideURL(override.id)
        let previous = try? Data(contentsOf: target)
        do {
            try FileManager.default.createDirectory(
                at: workspace.overridesDirectory, withIntermediateDirectories: true
            )
            try data.write(to: target, options: .atomic)
        } catch {
            return .rejected(errors: [makeError(
                file: fileLabel, field: "/",
                expected: "a writable overrides directory",
                message: "Override file could not be written.",
                remediation: "Check permissions on the state root."
            )])
        }

        switch loader.load() {
        case let .activated(active):
            // The candidate activated, but an override for a mode that does not
            // exist is dormant configuration — reject it so a caller cannot pin
            // apps to a mode id that is not configured.
            guard active.mode(id: override.id) != nil else {
                rollback(target: target, previous: previous)
                return .rejected(errors: [makeError(
                    file: fileLabel, field: "/id",
                    expected: "an existing mode id",
                    message: "Mode \"\(override.id)\" is not configured.",
                    remediation: "Use the id of a configured mode."
                )])
            }
            return .applied(active)
        case let .rejected(errors, _):
            rollback(target: target, previous: previous)
            return .rejected(errors: errors)
        }
    }

    /// Removes a mode's canonical override file, reverting that mode to its
    /// shipped default. Removing an absent override is a no-op that still
    /// reports the (re)activated configuration.
    public func remove(modeID: String) -> Outcome {
        let target = overrideURL(modeID)
        let previous = try? Data(contentsOf: target)
        if previous != nil {
            try? FileManager.default.removeItem(at: target)
        }
        switch loader.load() {
        case let .activated(active):
            return .applied(active)
        case let .rejected(errors, _):
            // Removal exposed an unrelated invalid override; restore the file so
            // the write path never leaves the disk in a different-but-still-
            // rejected state.
            rollback(target: target, previous: previous)
            return .rejected(errors: errors)
        }
    }

    private func overrideURL(_ modeID: String) -> URL {
        workspace.overridesDirectory.appendingPathComponent("\(modeID).json")
    }

    /// Restores the pre-write bytes (or absence) of the target file.
    private func rollback(target: URL, previous: Data?) {
        if let previous {
            try? previous.write(to: target, options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: target)
        }
    }

    private func makeError(
        file: String, field: String, expected: String, message: String, remediation: String
    ) -> CerebralHelmConfigValidationError {
        CerebralHelmConfigValidationError(
            expected: expected,
            field: field,
            file: file,
            message: message,
            remediation: remediation,
            schemaVersion: ConfigValidator.schemaVersion
        )
    }
}
