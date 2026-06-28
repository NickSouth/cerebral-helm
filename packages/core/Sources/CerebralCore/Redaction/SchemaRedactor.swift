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

    /// Extracts the leaf value(s) found at the given JSON-Pointer redaction
    /// `paths` in `json`, as strings. A path that does not resolve in the
    /// document is skipped (the same path list applies safely to a tool's input
    /// and its output). Scalars (string, number, bool) are rendered to their
    /// string form; container leaves are ignored because there is no single raw
    /// value to match against. Used to drive disclosure/plan redaction: the
    /// caller replaces any occurrence of a returned value with ``marker`` so a
    /// covered field cannot leak through an unredacted disclosure (NIC-110).
    public static func valuesAtPaths(_ json: Data, paths: [String]) -> [String] {
        guard !paths.isEmpty, let root = try? JSONSerialization.jsonObject(with: json) else {
            return []
        }

        var values: [String] = []
        for path in paths {
            let tokens = parsePointer(path)
            guard !tokens.isEmpty, let leaf = value(root, tokens: tokens[...]) else { continue }
            if let scalar = scalarString(leaf) {
                values.append(scalar)
            }
        }
        return values
    }

    private static func value(_ value: Any, tokens: ArraySlice<String>) -> Any? {
        guard let head = tokens.first else { return value }
        let tail = tokens.dropFirst()

        if let dictionary = value as? [String: Any], let child = dictionary[head] {
            return self.value(child, tokens: tail)
        }
        if let array = value as? [Any], let index = Int(head), array.indices.contains(index) {
            return self.value(array[index], tokens: tail)
        }
        return nil
    }

    private static func scalarString(_ value: Any) -> String? {
        switch value {
        case let string as String:
            return string
        case let bool as Bool:
            return bool ? "true" : "false"
        case let number as NSNumber:
            // JSON numbers arrive boxed as NSNumber; render the underlying value.
            return number.stringValue
        default:
            // Objects and arrays have no single raw value to match against.
            return nil
        }
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
