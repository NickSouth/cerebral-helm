import Foundation

/// The latest known status of a command, reconstructed from the event log.
public struct CommandStatusRecord: Equatable, Sendable {
    public let commandId: String
    public let status: CommandStatus
    public let message: String?
}

/// Reconstructs a command's current status by replaying the event log.
///
/// The CLI is stateless across invocations, so `command status` and `cancel`
/// read the persisted lifecycle events rather than an in-memory bus. Lines that
/// are not lifecycle events (e.g. simulation previews) are ignored.
public enum CommandStatusReader {
    public static func latest(commandId: String, eventLogPath: URL) throws -> CommandStatusRecord? {
        guard FileManager.default.fileExists(atPath: eventLogPath.path) else {
            return nil
        }
        let contents = try String(contentsOf: eventLogPath, encoding: .utf8)
        let decoder = CommandCoding.makeDecoder()

        var latest: CommandStatusRecord?
        for line in contents.split(omittingEmptySubsequences: true, whereSeparator: \.isNewline) {
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
}
