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
}
