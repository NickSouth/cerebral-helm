import Foundation

/// The user's minted URL references (NIC-146): a URL the user adds becomes a
/// per-mode quick app the same way a pinned app does, riding the same validated
/// config-write path and reference catalog as ``UserAppReferences``.
///
/// Unlike apps, URLs have no discovery source — the user types one — so minting
/// is a discrete `add`, not a reconcile-all. Minted entries live in
/// `references/urls.json` under the **state root** (user-owned, survives updates,
/// inspectable), the same document format as the shipped `config/references/urls.json`.
///
/// A minted target is always an `http`/`https` URL: this path can never mint a
/// `file://`, custom-scheme, or `javascript:` target, so a minted reference can
/// only ever open a web page (mirrors the `url.open` capability's contract).
/// The minted id is a slug of the label (or the host), deduplicated against every
/// known reference id — including apps — so `open <id>` can never resolve
/// ambiguously between a URL and an app reference.
public enum UserURLReferences {
    /// Why an add was refused. The URL was never minted for any of these.
    public enum AddError: Error, Equatable, Sendable {
        case emptyURL
        case invalidURL
        case unsupportedScheme
    }

    private struct CatalogFile: Codable {
        let schemaVersion: String
        let references: [ReferenceEntry]
    }

    public static func fileURL(stateRoot: URL) -> URL {
        stateRoot
            .appendingPathComponent("references", isDirectory: true)
            .appendingPathComponent("urls.json")
    }

    /// The persisted minted references; empty on a missing or unreadable file
    /// (degrade, never fail startup). Invalid ids are filtered on load.
    public static func load(stateRoot: URL) -> [ReferenceEntry] {
        guard
            let data = try? Data(contentsOf: fileURL(stateRoot: stateRoot)),
            let file = try? JSONDecoder().decode(CatalogFile.self, from: data)
        else { return [] }
        return file.references.filter { isValidID($0.id) }
    }

    /// Mints one URL reference from a user-entered URL (and optional label),
    /// persists the updated user catalog, and returns the new (or existing) entry.
    ///
    /// - A bare host (`github.com`) is treated as `https://github.com`.
    /// - Only `http`/`https` are accepted; anything else fails `unsupportedScheme`.
    /// - Idempotent by target: re-adding the same URL returns the existing entry
    ///   rather than minting a duplicate.
    /// - `existingIDs` must contain every already-configured reference id (apps and
    ///   URLs, shipped and user) so the minted id is globally unique.
    @discardableResult
    public static func add(
        url: String,
        label: String?,
        existingIDs: Set<String>,
        stateRoot: URL
    ) -> Result<ReferenceEntry, AddError> {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.emptyURL) }

        // A scheme-less entry defaults to https, so "github.com" is accepted.
        var candidate = trimmed
        if URLComponents(string: candidate)?.scheme == nil {
            candidate = "https://" + candidate
        }
        guard
            let components = URLComponents(string: candidate),
            let scheme = components.scheme?.lowercased()
        else { return .failure(.invalidURL) }
        guard scheme == "http" || scheme == "https" else { return .failure(.unsupportedScheme) }
        guard let host = components.host, !host.isEmpty else { return .failure(.invalidURL) }

        var minted = load(stateRoot: stateRoot)
        // Idempotent by target: the same URL already minted returns its entry.
        if let existing = minted.first(where: { $0.target == candidate }) {
            return .success(existing)
        }

        let trimmedLabel = label?.trimmingCharacters(in: .whitespacesAndNewlines)
        let labelText = (trimmedLabel?.isEmpty == false ? trimmedLabel : nil) ?? host
        let base = UserAppReferences.slug(labelText)
        let taken = existingIDs.union(minted.map(\.id))
        let id = uniqueID(base, taken: taken)

        let entry = ReferenceEntry(id: id, label: labelText, target: candidate)
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

    /// Reference ids must match the config-id grammar `^[a-z][a-z0-9-]*$`.
    private static func isValidID(_ id: String) -> Bool {
        id.range(of: "^[a-z][a-z0-9-]*$", options: .regularExpression) != nil
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
