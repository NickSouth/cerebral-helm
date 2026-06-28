import Foundation

/// Derives stable, file-safe note ids and filenames from human titles, matching
/// the note-metadata `id` pattern `^[a-z0-9][a-z0-9-]*$` so a note is safe on disk
/// and linkable (FR-KNW-02 naming rules).
public enum NoteNaming {
    /// A lowercase ASCII slug of `title`: alphanumerics are kept, every other run
    /// becomes a single hyphen, and leading/trailing hyphens are trimmed. A title
    /// with no usable characters falls back to `"note"`.
    public static func id(fromTitle title: String) -> String {
        var characters: [Character] = []
        var previousWasHyphen = false
        for scalar in title.lowercased().unicodeScalars {
            if (scalar >= "a" && scalar <= "z") || (scalar >= "0" && scalar <= "9") {
                characters.append(Character(scalar))
                previousWasHyphen = false
            } else if !previousWasHyphen {
                characters.append("-")
                previousWasHyphen = true
            }
        }

        var slug = String(characters)
        while slug.hasPrefix("-") { slug.removeFirst() }
        while slug.hasSuffix("-") { slug.removeLast() }
        return slug.isEmpty ? "note" : slug
    }

    /// The Markdown filename for a note id.
    public static func filename(forID id: String) -> String {
        "\(id).md"
    }

    /// A unique, file-safe capture id: the title slug plus a timestamp token. The
    /// CLI deliberately captures with a content-free title (NIC-34), so a bare slug
    /// would collide on every note; the timestamp makes normal captures unique
    /// while two captures at the same instant still collide (surfaced as a
    /// structured error, AC-44.3).
    public static func captureID(fromTitle title: String, at instant: Foundation.Date) -> String {
        "\(id(fromTitle: title))-\(timestampToken(instant))"
    }

    /// A compact, lowercase `[a-z0-9]` rendering of an instant, e.g.
    /// `20260628t143022123z`.
    public static func timestampToken(_ instant: Foundation.Date) -> String {
        let formatter = Foundation.ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let raw = formatter.string(from: instant).lowercased()
        return String(raw.unicodeScalars.filter { ($0 >= "a" && $0 <= "z") || ($0 >= "0" && $0 <= "9") })
    }
}
