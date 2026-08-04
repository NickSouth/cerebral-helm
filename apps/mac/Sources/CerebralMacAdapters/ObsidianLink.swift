import Foundation

/// Builds the `obsidian://` link that opens the user's knowledge root in Obsidian,
/// and decides what to do when Obsidian cannot take it (NIC-162).
///
/// Obsidian is the browsing surface for durable notes (owner decision): the notes
/// are plain Markdown, and Obsidian already reads them far better than a settings
/// panel could. CerebralHelm captures and indexes; Obsidian is where you read.
///
/// Verified against Obsidian's URI documentation:
/// - `obsidian://open?path=<absolute path>` overrides `vault`/`file`; Obsidian
///   resolves whichever registered vault contains the path.
/// - Values must be percent-encoded — notably `/` as `%2F` and spaces as `%20`.
/// - **Obsidian cannot open a folder it has never registered as a vault.** There
///   is no URI for "add this vault", so a first run needs the user to add the
///   folder in Obsidian once. Nothing here can detect that, so the surface says
///   so rather than appearing to fail silently.
public enum ObsidianLink {
    /// What the shell should do with a "browse notes" request.
    public enum Destination: Equatable, Sendable {
        /// Hand the root to Obsidian.
        case obsidian(URL)
        /// Obsidian is not installed: reveal the folder in Finder instead, so the
        /// action still does something honest and useful.
        case revealInFinder(URL)
    }

    /// The `obsidian://open` URL for a knowledge root.
    ///
    /// Every reserved character is escaped — a path may contain spaces, `&`, `#`,
    /// or non-ASCII — so the whole path arrives as one parameter value rather than
    /// being truncated at the first delimiter.
    public static func openURL(forRoot root: URL) -> URL? {
        // `alphanumerics` only: everything else, `/` included, is percent-encoded,
        // which is what the URI documentation asks for.
        guard let encoded = root.standardizedFileURL.path
            .addingPercentEncoding(withAllowedCharacters: .alphanumerics)
        else { return nil }
        return URL(string: "obsidian://open?path=\(encoded)")
    }

    /// Where a browse request should go, given whether Obsidian can handle
    /// `obsidian://` on this Mac.
    public static func destination(forRoot root: URL, obsidianInstalled: Bool) -> Destination {
        guard obsidianInstalled, let url = openURL(forRoot: root) else {
            return .revealInFinder(root)
        }
        return .obsidian(url)
    }

    /// The `obsidian://open` URL for one **note** (quick actions phase 5).
    ///
    /// The same `path=` parameter as the root, and for the same documented reason:
    /// `path` overrides `vault`/`file`, so Obsidian resolves whichever registered
    /// vault contains the file without this having to know the vault's name.
    ///
    /// It takes an absolute path the knowledge service has already range-checked.
    /// Nothing here re-derives one from a root and a relative path — that join is
    /// precisely where a containment rule gets accidentally re-implemented, and a
    /// second rule could only disagree with the first.
    public static func openURL(forNote absolutePath: String) -> URL? {
        guard !absolutePath.isEmpty else { return nil }
        return openURL(forRoot: URL(fileURLWithPath: absolutePath))
    }

    /// Where a note-open request should go. Identical policy to a browse request:
    /// with no `obsidian://` handler the file is revealed in Finder instead, so the
    /// action still does something real and the caller is told which happened.
    public static func destination(forNote absolutePath: String, obsidianInstalled: Bool) -> Destination {
        let fileURL = URL(fileURLWithPath: absolutePath)
        guard obsidianInstalled, let url = openURL(forNote: absolutePath) else {
            return .revealInFinder(fileURL)
        }
        return .obsidian(url)
    }
}
