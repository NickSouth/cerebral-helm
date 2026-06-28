import Foundation

/// The active project / working context, persisted separately from the active
/// mode (FR-MOD-05). Kept deliberately small for the MVP: a stable id plus an
/// optional human label. A richer project entity is future work, so context is
/// round-tripped as-is and a corrupt store degrades to "no context".
public struct ProjectContext: Codable, Equatable, Sendable {
    public let id: String
    public let label: String?

    public init(id: String, label: String? = nil) {
        self.id = id
        self.label = label
    }
}

/// Persists the active mode and the active project/context **separately**
/// (FR-MOD-05), so one can change or fall back without disturbing the other. A
/// missing or unreadable value loads as `nil` rather than throwing, leaving the
/// resolver to choose a safe default.
///
/// This is the durable-state port. The pre-Mac foundation binds a file adapter
/// (`CerebralTools.FileModeStateStore`); NIC-42 PRE-DATA swaps a SQLite-backed
/// adapter behind the same port.
public protocol ModeStateStore: Sendable {
    func loadActiveModeID() throws -> String?
    func saveActiveModeID(_ modeID: String?) throws
    func loadActiveContext() throws -> ProjectContext?
    func saveActiveContext(_ context: ProjectContext?) throws
}

/// Chooses a valid active mode on restore (FR-MOD-05): the persisted mode when it
/// still exists in the current configuration, otherwise the configured default.
/// A reference that no longer resolves never leaves the workspace stuck on a
/// missing mode (AC: missing references fall back safely).
public enum ModeStateResolver {
    public static func resolveActiveModeID(
        persisted: String?,
        availableModeIDs: Set<String>,
        defaultModeID: String
    ) -> String {
        if let persisted, availableModeIDs.contains(persisted) { return persisted }
        return defaultModeID
    }
}
