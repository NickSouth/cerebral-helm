// Chrome profile discovery (NIC-151 follow-up). The user opens apps/URLs in a
// specific Google Chrome profile via `--profile-directory` — but that flag takes
// Chrome's on-disk *directory* name ("Default", "Profile 1"), not the display
// name the user recognizes ("Nick", "Work"). Free text made that a foot-gun, so
// the UI offers a dropdown of the real profiles instead. This is the read-only
// enumeration behind it: directory name (the flag value), display name (shown to
// the user), and the profile avatar (rendered as a corner badge on tiles).
//
// This is not a gated tool — there is no descriptor or handler. `BridgeSession`
// drives it directly off `listChromeProfiles`, the same way it drives the
// favicon fetcher (NIC-147). The live implementation lives in `apps/mac`; this
// portable layer owns the port, the value type, and the mock.

/// One Google Chrome profile, discovered read-only.
public struct ChromeProfile: Equatable, Sendable {
    /// The `--profile-directory` value — Chrome's on-disk directory name
    /// (e.g. "Default", "Profile 1"). This is what a reference stores in `profile`.
    public let directory: String
    /// The user-facing display name (e.g. "Nick", "Work"), for the dropdown label.
    public let name: String
    /// The profile avatar as a size-capped base64 PNG, or nil when none could be
    /// produced — the UI falls back to a generic glyph, never invents one.
    public let iconPNGBase64: String?

    public init(directory: String, name: String, iconPNGBase64: String?) {
        self.directory = directory
        self.name = name
        self.iconPNGBase64 = iconPNGBase64
    }
}

/// Read-only enumeration of the Chrome profiles configured on this machine.
/// Never launches Chrome, never writes — it only reads Chrome's profile metadata.
public protocol ChromeProfileDiscoveryCapability: Sendable {
    func listProfiles() async throws -> [ChromeProfile]
}
