import CerebralTools

/// Resolves the "Layout display" setting (NIC-142) to a ``WindowDisplay`` for the
/// layout arrange, given the current topology. Pure and dependency-free so it is
/// unit-testable; the caller supplies the persisted ids and a flattened display list.
///
/// Semantics: an explicit layout id wins; the `system-primary` sentinel means "same as
/// the main display", so it falls back to the main-display id. A target that names a
/// connected, stable-identity display maps to `.primary` when that display is the OS
/// primary, else `.secondary`. Anything unset, unknown, or disconnected degrades to
/// `.primary` — the main/default screen — mirroring the main-display degradation.
///
/// The primary/secondary mapping is exact for a two-display setup (the layout display is
/// either the primary or "the other one"); with three or more displays `.secondary`
/// resolves to the first non-primary screen, which the arrange already targets.
public enum LayoutDisplayResolver {
    /// The sentinel persisted for "unset" / "same as main display".
    public static let sentinel = "system-primary"

    /// One connected display, flattened from the topology.
    public struct Display: Equatable, Sendable {
        public let id: String
        public let primary: Bool
        public let stableIdentity: Bool
        public init(id: String, primary: Bool, stableIdentity: Bool) {
            self.id = id
            self.primary = primary
            self.stableIdentity = stableIdentity
        }
    }

    public static func resolve(
        layoutDisplayID: String?,
        mainDisplayID: String?,
        displays: [Display]
    ) -> WindowDisplay {
        // A layout id of nil or the sentinel means "same as the main display".
        let layoutID = layoutDisplayID.flatMap { $0 == sentinel ? nil : $0 }
        let mainID = mainDisplayID.flatMap { $0 == sentinel ? nil : $0 }
        guard
            let targetID = layoutID ?? mainID,
            let match = displays.first(where: { $0.id == targetID && $0.stableIdentity })
        else {
            return .primary
        }
        return match.primary ? .primary : .secondary
    }
}
