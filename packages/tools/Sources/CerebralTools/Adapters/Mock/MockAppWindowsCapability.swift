import CerebralCore

/// Deterministic mock ``AppWindowsCapability`` for the window navigator (NIC-143).
/// Serves a fixed grouped inventory; minimize/surface/close report whether the id
/// exists in that inventory, mirroring the native adapter's best-effort semantics
/// without any platform API. A reference type so a test can observe which window ids
/// were acted on.
public final class MockAppWindowsCapability: AppWindowsCapability, @unchecked Sendable {
    public let groups: [AppWindowGroup]
    public private(set) var minimized: [String] = []
    public private(set) var surfaced: [String] = []
    public private(set) var closed: [String] = []

    public init(groups: [AppWindowGroup] = MockAppWindowsCapability.sampleGroups) {
        self.groups = groups
    }

    private var knownIDs: Set<String> {
        Set(groups.flatMap { $0.windows.map(\.id) })
    }

    public func listWindows() async throws -> [AppWindowGroup] { groups }

    public func minimize(windowID: String) async throws -> Bool {
        guard knownIDs.contains(windowID) else { return false }
        minimized.append(windowID)
        return true
    }

    public func surface(windowID: String) async throws -> Bool {
        guard knownIDs.contains(windowID) else { return false }
        surfaced.append(windowID)
        return true
    }

    public func close(windowID: String) async throws -> Bool {
        guard knownIDs.contains(windowID) else { return false }
        closed.append(windowID)
        return true
    }

    /// A representative two-app inventory (a multi-window app plus a single-window
    /// app), for tests and browser previews of the navigator.
    public static let sampleGroups: [AppWindowGroup] = [
        AppWindowGroup(bundleID: "com.google.Chrome", appName: "Google Chrome", windows: [
            AppWindowInfo(id: "1001", title: "Inbox — Gmail", minimized: false),
            AppWindowInfo(id: "1002", title: "CerebralHelm · GitHub", minimized: true),
        ]),
        AppWindowGroup(bundleID: "com.microsoft.VSCode", appName: "Visual Studio Code", windows: [
            AppWindowInfo(id: "2001", title: "BridgeSession.swift — cerebral-helm", minimized: false),
        ]),
    ]
}
