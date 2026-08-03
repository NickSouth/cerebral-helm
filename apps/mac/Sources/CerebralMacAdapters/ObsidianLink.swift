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
}
