/// A structured, user-facing explanation of a storage failure plus what to do
/// about it (FR-KNW-07, FR-SHL-05).
///
/// Codes match the canonical storage-failure fixtures
/// (`fixtures/catalog/canonical-states.json`). A diagnostic never implies a repair
/// was attempted — recovery is surfaced, not performed automatically, so user data
/// is never silently discarded (AC-49.3).
public struct RecoveryDiagnostic: Equatable, Sendable {
    /// Which store failed: `knowledge` or `operational_sqlite`.
    public let store: String
    /// Canonical, stable error code (e.g. `knowledge_root_missing`, `sqlite_locked`).
    public let code: String
    /// What happened.
    public let summary: String
    /// What the user can do about it.
    public let guidance: String

    public init(store: String, code: String, summary: String, guidance: String) {
        self.store = store
        self.code = code
        self.summary = summary
        self.guidance = guidance
    }
}

public extension RecoveryDiagnostic {
    /// Maps a knowledge failure to recovery guidance (AC-49.1).
    static func forKnowledge(_ error: KnowledgeServiceError) -> RecoveryDiagnostic {
        switch error {
        case .rootUnavailable:
            return RecoveryDiagnostic(
                store: "knowledge",
                code: "knowledge_root_missing",
                summary: "The configured Markdown knowledge root does not exist.",
                guidance: "Choose or restore the knowledge root, then retry. No note was written."
            )
        case .rootReadOnly:
            return RecoveryDiagnostic(
                store: "knowledge",
                code: "knowledge_root_read_only",
                summary: "The knowledge root is readable but cannot accept writes.",
                guidance: "Grant write access to the knowledge root or pick a writable location. Existing notes are untouched."
            )
        case let .collision(message):
            return RecoveryDiagnostic(
                store: "knowledge",
                code: "knowledge_note_collision",
                summary: message,
                guidance: "Use a different title, or remove the existing note first. The existing note was not overwritten."
            )
        case let .writeFailed(message):
            return RecoveryDiagnostic(
                store: "knowledge",
                code: "knowledge_write_failed",
                summary: message,
                guidance: "Check available disk space and permissions, then retry."
            )
        case let .noteNotFound(message):
            return RecoveryDiagnostic(
                store: "knowledge",
                code: "knowledge_note_missing",
                summary: message,
                guidance: "The note may have been renamed, moved, or deleted outside CerebralHelm. Re-list the notes to see the current paths. Nothing was changed."
            )
        }
    }
}

/// The result of the read-only startup pre-flight (FR-SHL-05).
public enum StartupCheck: Equatable, Sendable {
    /// Data paths and schema are valid; writes may proceed.
    case ready
    /// One or more validations failed; the system stays read-only and surfaces
    /// these diagnostics. No user data was mutated to reach this state (AC-49.2).
    case recovery([RecoveryDiagnostic])
}
