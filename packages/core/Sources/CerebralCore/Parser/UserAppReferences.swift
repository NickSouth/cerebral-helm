import Foundation

/// The user's auto-minted app references (NIC-119, owner decision 2026-07-06):
/// every installed application discovered without a configured reference gets
/// one minted automatically, so all apps are pinnable and openable by id —
/// no manual catalog curation.
///
/// Minted entries live in `references/apps.json` under the **state root**
/// (user-owned, survives updates, inspectable), same document format as the
/// shipped `config/references/apps.json`. Targets are always the discovered
/// bundle identifier — this path can never mint an arbitrary executable path.
/// Shipped references win on id and target; a minted id is a slug of the app's
/// display name, deduplicated with numeric suffixes and stable once written.
public enum UserAppReferences {
    private struct CatalogFile: Codable {
        let schemaVersion: String
        let references: [ReferenceEntry]
    }

    public static func fileURL(stateRoot: URL) -> URL {
        stateRoot
            .appendingPathComponent("references", isDirectory: true)
            .appendingPathComponent("apps.json")
    }

    /// The persisted minted references; empty on a missing or unreadable file
    /// (degrade, never fail startup — re-minting restores it).
    public static func load(stateRoot: URL) -> [ReferenceEntry] {
        guard
            let data = try? Data(contentsOf: fileURL(stateRoot: stateRoot)),
            let file = try? JSONDecoder().decode(CatalogFile.self, from: data)
        else { return [] }
        return file.references.filter { isValidID($0.id) }
    }

    /// One discovered application, as the minting input.
    public struct DiscoveredApp: Equatable, Sendable {
        public let bundleID: String
        public let name: String

        public init(bundleID: String, name: String) {
            self.bundleID = bundleID
            self.name = name
        }
    }

    /// Mints references for every discovered app whose bundle id no existing
    /// reference targets, persists the updated user catalog when anything was
    /// minted, and returns the full user catalog. Idempotent: already-minted
    /// and shipped-referenced apps mint nothing; ids stay stable across runs.
    @discardableResult
    public static func mint(
        discovered: [DiscoveredApp],
        shipped: [ReferenceEntry],
        stateRoot: URL
    ) -> [ReferenceEntry] {
        var minted = load(stateRoot: stateRoot)
        var knownTargets = Set(shipped.map(\.target)).union(minted.map(\.target))
        var knownIDs = Set(shipped.map(\.id)).union(minted.map(\.id))
        var mintedAnything = false

        for app in discovered where !knownTargets.contains(app.bundleID) {
            let id = uniqueID(slug(app.name), taken: knownIDs)
            minted.append(ReferenceEntry(id: id, label: app.name, target: app.bundleID))
            knownTargets.insert(app.bundleID)
            knownIDs.insert(id)
            mintedAnything = true
        }

        if mintedAnything {
            persist(minted, stateRoot: stateRoot)
        }
        return minted
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

    /// "Visual Studio Code" → "visual-studio-code"; anything that slugs to an
    /// invalid or empty id gets the neutral `app` stem (then deduplicated).
    static func slug(_ name: String) -> String {
        let lowered = name.lowercased()
        var out = ""
        var lastWasDash = true // suppress leading dashes
        for scalar in lowered.unicodeScalars {
            if ("a"..."z").contains(String(scalar)) || ("0"..."9").contains(String(scalar)) {
                out.append(Character(scalar))
                lastWasDash = false
            } else if !lastWasDash {
                out.append("-")
                lastWasDash = true
            }
        }
        while out.hasSuffix("-") {
            out.removeLast()
        }
        if isValidID(out) {
            return out
        }
        // Starts with a digit or emptied out entirely: give it a letter stem.
        return isValidID("app-" + out) ? "app-" + out : "app"
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
