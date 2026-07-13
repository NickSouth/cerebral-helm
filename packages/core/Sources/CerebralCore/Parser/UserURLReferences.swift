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
        /// The Chrome profile contained characters outside the allowed set — a
        /// guard against smuggling extra launch flags into `--profile-directory`
        /// (NIC-151). Mirrors the reference-catalog schema `profile` pattern.
        case invalidProfile
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
    /// - `profile` is an optional Google Chrome profile directory (NIC-151): when
    ///   present the minted reference opens in that Chrome profile. It is validated
    ///   against the same pattern as the reference-catalog schema; an empty/blank
    ///   value is treated as no profile. An invalid value fails `invalidProfile`.
    /// - Idempotent by `(target, profile)`: re-adding the same URL *with the same
    ///   profile* returns the existing entry, but the same URL with a different
    ///   profile mints a distinct reference — so a site like Gmail can be pinned
    ///   once per profile (work vs personal).
    /// - `existingIDs` must contain every already-configured reference id (apps and
    ///   URLs, shipped and user) so the minted id is globally unique.
    @discardableResult
    public static func add(
        url: String,
        label: String?,
        profile: String? = nil,
        existingIDs: Set<String>,
        stateRoot: URL
    ) -> Result<ReferenceEntry, AddError> {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.emptyURL) }

        // A blank profile is simply "no profile"; a non-blank one must match the
        // allowed set, so it cannot carry extra `--profile-directory` flags.
        let trimmedProfile = profile?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedProfile = (trimmedProfile?.isEmpty == false) ? trimmedProfile : nil
        if let normalizedProfile, !isValidProfile(normalizedProfile) {
            return .failure(.invalidProfile)
        }

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
        // Idempotent by (target, profile): the same URL+profile returns its entry,
        // but the same URL under a different profile is a distinct pin.
        if let existing = minted.first(where: { $0.target == candidate && $0.profile == normalizedProfile }) {
            return .success(existing)
        }

        let trimmedLabel = label?.trimmingCharacters(in: .whitespacesAndNewlines)
        let labelText = (trimmedLabel?.isEmpty == false ? trimmedLabel : nil) ?? host
        let base = UserAppReferences.slug(labelText)
        let taken = existingIDs.union(minted.map(\.id))
        let id = uniqueID(base, taken: taken)

        let entry = ReferenceEntry(id: id, label: labelText, target: candidate, profile: normalizedProfile)
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

    /// Chrome profile directories must match the reference-catalog schema pattern
    /// `^[A-Za-z0-9 ._-]+$`, so a profile value cannot inject extra launch flags.
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
