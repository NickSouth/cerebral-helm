import Foundation

/// The runtime-held state of an active layout (NIC-142): which windows a mode's
/// authored layout put on screen and the dynamic quick-toggle slot, if any.
///
/// Ephemeral, runtime-only state (like a pending confirmation) — not durable. It
/// is started when a layout is opened and cleared on close or a mode switch. The
/// UI-facing shape is ``LayoutSessionSnapshot`` (delivered by the
/// `layout.session.changed` event); the session additionally carries each app
/// window's bundle id so `closeLayout` can hide it.
struct LayoutSession: Sendable {
    let modeID: String
    let windows: [LayoutSessionWindow]
    let quickToggle: LayoutSessionToggle?

    /// Every app window's bundle id (static windows + quick-toggle targets). URL
    /// windows have no bundle id and are omitted — they cannot be hidden by the
    /// application-level workspace capability.
    var appBundleIDs: [String] {
        (windows + (quickToggle?.targets ?? [])).compactMap(\.bundleID)
    }

    /// A copy with the quick-toggle slot showing `ref` (NIC-142). No-op when there
    /// is no toggle slot.
    func withActiveToggle(_ ref: String) -> LayoutSession {
        guard let toggle = quickToggle else { return self }
        return LayoutSession(
            modeID: modeID,
            windows: windows,
            quickToggle: LayoutSessionToggle(activeRef: ref, targets: toggle.targets)
        )
    }

    var snapshot: LayoutSessionSnapshot {
        LayoutSessionSnapshot(
            modeId: modeID,
            windows: windows.map(\.snapshot),
            quickToggle: quickToggle.map {
                LayoutSessionSnapshot.Toggle(activeRef: $0.activeRef, targets: $0.targets.map(\.snapshot))
            }
        )
    }
}

struct LayoutSessionWindow: Sendable {
    let ref: String
    /// "app" or "url" (the authored layout's reference kind).
    let kind: String
    /// The reference's human label, for the bottom-bar chip.
    let label: String
    /// The application bundle id, when this is an app reference. nil for URLs.
    let bundleID: String?

    var snapshot: LayoutSessionSnapshot.Window {
        LayoutSessionSnapshot.Window(ref: ref, kind: kind, label: label)
    }
}

struct LayoutSessionToggle: Sendable {
    /// The reference currently shown in the dynamic slot (the first target on open).
    let activeRef: String
    let targets: [LayoutSessionWindow]
}

/// The UI-facing layout-session payload (no bundle ids — the dashboard addresses
/// windows by reference id).
struct LayoutSessionSnapshot: Encodable {
    let modeId: String
    let windows: [Window]
    let quickToggle: Toggle?

    struct Window: Encodable {
        let ref: String
        let kind: String
        let label: String
    }

    struct Toggle: Encodable {
        let activeRef: String
        let targets: [Window]
    }
}
