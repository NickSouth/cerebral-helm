import Foundation
import CerebralCore

/// File-backed ``ModeStateStore`` for the pre-Mac foundation.
///
/// The active mode and active context live in **separate** JSON files under the
/// env-aware state root (FR-MOD-05), each written atomically so an interrupted
/// write cannot corrupt the other or leave a half-written file. A missing or
/// unreadable file loads as `nil`, so a fresh workspace — or a corrupted line —
/// degrades to safe defaults rather than failing. NIC-42 PRE-DATA swaps a
/// SQLite-backed adapter behind the same port.
public struct FileModeStateStore: ModeStateStore {
    private struct ActiveModeFile: Codable { let activeModeId: String? }

    private let activeModePath: URL
    private let activeContextPath: URL

    public init(activeModePath: URL, activeContextPath: URL) {
        self.activeModePath = activeModePath
        self.activeContextPath = activeContextPath
    }

    public func loadActiveModeID() throws -> String? {
        guard let file: ActiveModeFile = decodeIfPresent(activeModePath) else { return nil }
        return file.activeModeId
    }

    public func saveActiveModeID(_ modeID: String?) throws {
        try writeAtomically(ActiveModeFile(activeModeId: modeID), to: activeModePath)
    }

    public func loadActiveContext() throws -> ProjectContext? {
        decodeIfPresent(activeContextPath)
    }

    public func saveActiveContext(_ context: ProjectContext?) throws {
        guard let context else {
            // Clearing context removes the file so a stale value cannot reappear.
            if FileManager.default.fileExists(atPath: activeContextPath.path) {
                try FileManager.default.removeItem(at: activeContextPath)
            }
            return
        }
        try writeAtomically(context, to: activeContextPath)
    }

    // MARK: - Internals

    private func decodeIfPresent<T: Decodable>(_ url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func writeAtomically<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        try encoder.encode(value).write(to: url, options: .atomic)
    }
}
