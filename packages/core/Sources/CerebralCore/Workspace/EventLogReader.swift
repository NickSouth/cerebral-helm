import Foundation

/// Reads the tail of the development event log (newline-delimited JSON).
///
/// The log is the cross-invocation event record the CLI's `events tail` reads.
/// The command bus writes to it once the action surfaces land (NIC-26 part 2);
/// until then a missing or empty log returns no entries rather than failing.
public enum EventLogReader {
    /// Returns the last `lines` non-empty entries, oldest first. A missing log
    /// yields an empty array.
    public static func tail(_ eventLogPath: URL, lines: Int) throws -> [String] {
        guard lines > 0, FileManager.default.fileExists(atPath: eventLogPath.path) else {
            return []
        }
        let contents = try String(contentsOf: eventLogPath, encoding: .utf8)
        let entries = contents
            .split(omittingEmptySubsequences: true, whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.isEmpty }
        return Array(entries.suffix(lines))
    }
}
