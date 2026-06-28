import Foundation

/// The latest known status of a command, reconstructed from the event log.
public struct CommandStatusRecord: Equatable, Sendable {
    public let commandId: String
    public let status: CommandStatus
    public let message: String?
}

/// Reconstructs a command's current status by replaying its lifecycle events.
///
/// The CLI is stateless across invocations, so `command status` and `cancel`
/// replay the persisted events rather than an in-memory bus. The pure
/// ``latest(commandId:eventLines:)`` is fed event JSON from whatever store owns it
/// — SQLite is the source of truth (NIC-47); the file overload remains for the
/// demoted NDJSON adapter and tests. Lines that are not lifecycle events (e.g.
/// simulation previews) are ignored.
public enum CommandStatusReader {
    /// Replays event JSON lines (oldest first), returning the latest status for
    /// `commandId`.
    public static func latest(commandId: String, eventLines: [String]) -> CommandStatusRecord? {
        let decoder = CommandCoding.makeDecoder()
        var latest: CommandStatusRecord?
        for line in eventLines {
            guard let event = try? decoder.decode(CommandLifecycleEvent.self, from: Data(line.utf8)),
                  event.commandID == commandId
            else { continue }
            latest = CommandStatusRecord(
                commandId: commandId,
                status: event.currentStatus,
                message: event.message
            )
        }
        return latest
    }

    /// Demoted NDJSON adapter: replays events from a file event log.
    public static func latest(commandId: String, eventLogPath: URL) throws -> CommandStatusRecord? {
        guard FileManager.default.fileExists(atPath: eventLogPath.path) else {
            return nil
        }
        let contents = try String(contentsOf: eventLogPath, encoding: .utf8)
        let lines = contents
            .split(omittingEmptySubsequences: true, whereSeparator: \.isNewline)
            .map(String.init)
        return latest(commandId: commandId, eventLines: lines)
    }
}
