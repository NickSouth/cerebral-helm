import Foundation

/// Redacts declared sensitive paths in a JSON object before it is logged,
/// persisted, or displayed (FR-OBS-03, NIC-34).
///
/// Paths are JSON Pointers taken from a tool descriptor's `logging.redactionPaths`
/// (e.g. `/body`, `/environment`, `/stdout`). A matched value is replaced with a
/// fixed marker; non-sensitive siblings are preserved, and a path that does not
/// resolve in a given document is ignored — so the same path list applies safely
/// to both a tool's input and its output.
public enum SchemaRedactor {
    public static let marker = "[REDACTED]"

    public static func redact(_ json: Data, paths: [String]) -> Data {
        guard !paths.isEmpty, let root = try? JSONSerialization.jsonObject(with: json) else {
            return json
        }

        var current = root
        for path in paths {
            let tokens = parsePointer(path)
            guard !tokens.isEmpty else { continue }
            current = redact(current, tokens: tokens[...])
        }

        guard
            JSONSerialization.isValidJSONObject(current),
            let data = try? JSONSerialization.data(withJSONObject: current, options: [.sortedKeys])
        else { return json }
        return data
    }

    private static func parsePointer(_ pointer: String) -> [String] {
        guard pointer.hasPrefix("/") else { return [] }
        return pointer.dropFirst().components(separatedBy: "/").map {
            $0.replacingOccurrences(of: "~1", with: "/").replacingOccurrences(of: "~0", with: "~")
        }
    }

    private static func redact(_ value: Any, tokens: ArraySlice<String>) -> Any {
        guard let head = tokens.first else { return marker }
        let tail = tokens.dropFirst()

        if var dictionary = value as? [String: Any] {
            if let child = dictionary[head] {
                dictionary[head] = redact(child, tokens: tail)
            }
            return dictionary
        }
        if var array = value as? [Any], let index = Int(head), array.indices.contains(index) {
            array[index] = redact(array[index], tokens: tail)
            return array
        }
        return value
    }
}
