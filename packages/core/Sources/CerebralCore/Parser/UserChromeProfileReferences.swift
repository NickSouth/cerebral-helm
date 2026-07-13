import Foundation

/// The user's pinned Chrome-profile app references (NIC-151): pinning a Chrome
/// profile from the More Apps picker mints an app reference that opens Google
/// Chrome in that profile, so it rides the same reference catalog and quick-app
/// pinning path as any other app.
///
/// Each entry targets `com.google.Chrome` and carries the profile *directory*
/// name in `profile`, so `app.open` launches it with `--profile-directory`. Unlike
/// ``UserAppReferences`` (which reconciles against discovered apps and dedupes by
/// bundle id), these deliberately share one bundle id across many entries — one
/// per profile — so they live in their own store, keyed by (target, profile), and
/// are never pruned by app reconciliation.
///
/// Persisted under `<stateRoot>/references/chrome-profiles.json`, the same document
/// shape as the other reference catalogs, and merged into the app catalog by
/// ``ReferenceCatalogLoader`` (id-only dedup, so the shared Chrome bundle id does
/// not collapse distinct profiles).
public enum UserChromeProfileReferences {
    /// Chrome's bundle identifier — the fixed target of every entry.
    public static let chromeBundleID = "com.google.Chrome"

    /// Why an add was refused. Nothing was minted for any of these.
    public enum AddError: Error, Equatable, Sendable {
        case emptyDirectory
        /// The profile directory contained characters outside the allowed set — the
        /// same `--profile-directory` injection guard as the reference schema.
        case invalidProfile
    }

    private struct CatalogFile: Codable {
        let schemaVersion: String
        let references: [ReferenceEntry]
    }

    public static func fileURL(stateRoot: URL) -> URL {
        stateRoot
            .appendingPathComponent("references", isDirectory: true)
            .appendingPathComponent("chrome-profiles.json", isDirectory: false)
    }

    /// The persisted entries; empty on a missing or unreadable file (degrade, never
    /// fail startup). Entries with an invalid id or no profile are filtered on load.
    public static func load(stateRoot: URL) -> [ReferenceEntry] {
        guard
            let data = try? Data(contentsOf: fileURL(stateRoot: stateRoot)),
            let file = try? JSONDecoder().decode(CatalogFile.self, from: data)
        else { return [] }
        return file.references.filter { isValidID($0.id) && $0.profile != nil }
    }

    /// Mints an app reference opening Chrome in `directory`, persists it, and returns
    /// it. Idempotent by profile directory: re-pinning the same profile returns the
    /// existing entry rather than a duplicate. `existingIDs` must contain every
    /// configured reference id so the minted id is globally unique.
    @discardableResult
    public static func add(
        directory: String,
        name: String?,
        existingIDs: Set<String>,
        stateRoot: URL
    ) -> Result<ReferenceEntry, AddError> {
        let trimmedDirectory = directory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDirectory.isEmpty else { return .failure(.emptyDirectory) }
        guard isValidProfile(trimmedDirectory) else { return .failure(.invalidProfile) }

        var minted = load(stateRoot: stateRoot)
        if let existing = minted.first(where: { $0.profile == trimmedDirectory }) {
            return .success(existing)
        }

        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = (trimmedName?.isEmpty == false ? trimmedName : nil) ?? trimmedDirectory
        let label = "Chrome — \(displayName)"
        let base = "chrome-\(UserAppReferences.slug(displayName))"
        let taken = existingIDs.union(minted.map(\.id))
        let id = uniqueID(base, taken: taken)

        let entry = ReferenceEntry(id: id, label: label, target: chromeBundleID, profile: trimmedDirectory)
        minted.append(entry)
        persist(minted, stateRoot: stateRoot)
        return .success(entry)
    }

    // MARK: - Internals

    private static func persist(_ references: [ReferenceEntry], stateRoot: URL) {
        let file = CatalogFile(schemaVersion: "1.0.0", references: references)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(file) else { return }
        let url = fileURL(stateRoot: stateRoot)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? data.write(to: url, options: .atomic)
    }

    private static func isValidID(_ id: String) -> Bool {
        id.range(of: "^[a-z][a-z0-9-]*$", options: .regularExpression) != nil
    }

    private static func isValidProfile(_ profile: String) -> Bool {
        profile.range(of: "^[A-Za-z0-9 ._-]+$", options: .regularExpression) != nil
    }

    private static func uniqueID(_ base: String, taken: Set<String>) -> String {
        guard taken.contains(base) else { return base }
        var counter = 2
        while taken.contains("\(base)-\(counter)") {
            counter += 1
        }
        return "\(base)-\(counter)"
    }
}
