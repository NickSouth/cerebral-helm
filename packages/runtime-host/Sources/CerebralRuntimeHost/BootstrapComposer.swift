import Foundation
import CerebralContracts
import CerebralCore

/// Composes the dashboard bootstrap state (NIC-74b) from validated configuration.
///
/// The four mode views and the fixed agent roster are derived from the user's real
/// config (`ConfigValidator`) — mode views map field-for-field, and an agent's
/// configured `status` is its availability. The region data, Heimlich surface, and
/// ambient channels are reported in their honest pre-adapter state (empty /
/// unavailable) until the live providers land (FR-SHL-06); counts default to zero
/// for a fresh session. Live region data and real counts are a follow-on increment.
public enum BootstrapComposer {
    /// The canonical mode display order (design spec / `tokens.ts` MODE_IDS). Config
    /// files enumerate in filesystem order, so the composer imposes this order rather
    /// than shipping an alphabetical roster the shell would render in the wrong order.
    private static let canonicalModeOrder = ["executive", "developer", "school", "entertainment"]

    /// Composes the bootstrap state. `activeModeID`, when supplied, sets the active
    /// mode (used by a mode switch to re-theme); otherwise the configured default.
    ///
    /// Shipped-defaults only — no user-overrides layer. Surfaces with a workspace
    /// (the shell) compose through ``compose(workspace:activeModeID:)`` instead so
    /// pinned quick apps appear; this entry remains for tests and workspace-less
    /// hosts.
    public static func compose(
        configDirectory: URL, activeModeID: String? = nil
    ) -> CerebralHelmBridgeBootstrapState {
        var modeConfigs: [CerebralHelmModeConfig] = []
        var agentConfigs: [CerebralHelmAgentSurfaceConfig] = []
        var defaultModeID: String?
        if case let .valid(config) = ConfigValidator.validate(configDirectory: configDirectory) {
            modeConfigs = config.modes
            agentConfigs = config.agents
            defaultModeID = config.defaults.defaultModeID
        }
        return compose(
            modes: modeConfigs, agents: agentConfigs,
            defaultModeID: defaultModeID, activeModeID: activeModeID
        )
    }

    /// Composes the bootstrap state through the layered ``ConfigLoader`` — the
    /// user-overrides read side (NIC-119c): pinned quick apps live in per-mode
    /// override files under the state root, so a workspace-aware surface must
    /// compose from the activated (merged) configuration, never the shipped
    /// defaults alone. A rejected candidate falls back to the last-known-good
    /// snapshot, then to the shipped defaults (FR-CFG-02).
    public static func compose(
        workspace: WorkspacePaths, activeModeID: String? = nil
    ) -> CerebralHelmBridgeBootstrapState {
        let active: ActiveConfig?
        switch ConfigLoader(workspace: workspace).load() {
        case let .activated(config):
            active = config
        case let .rejected(_, lastKnownGood):
            active = lastKnownGood
        }
        guard let active else {
            return compose(configDirectory: workspace.configDirectory, activeModeID: activeModeID)
        }
        return compose(
            modes: active.modes, agents: active.agents,
            defaultModeID: active.defaults.defaultModeID, activeModeID: activeModeID
        )
    }

    /// The single composition core: validated (possibly override-merged) configs in,
    /// bootstrap state out.
    private static func compose(
        modes modeConfigs: [CerebralHelmModeConfig],
        agents agentConfigs: [CerebralHelmAgentSurfaceConfig],
        defaultModeID: String?,
        activeModeID: String?
    ) -> CerebralHelmBridgeBootstrapState {
        let modeConfigs = orderedModes(modeConfigs)
        let modes = modeConfigs.compactMap { try? modeView($0) }
        let agents = agentConfigs.map { config in
            DashboardAgentSummary(
                activity: .idle,
                availability: config.status,
                id: config.id,
                label: config.label,
                summary: config.summary
            )
        }

        return CerebralHelmBridgeBootstrapState(
            agents: agents,
            commandsToday: 0,
            expandedAgent: nil,
            heimlich: idleHeimlich(),
            mode: resolveMode(defaultID: activeModeID ?? defaultModeID, modes: modeConfigs),
            modes: modes,
            pendingConfirmations: 0,
            project: "CerebralHelm",
            regions: degradedRegions(),
            schemaVersion: "1.0.0",
            summary: "Ready.",
            uiState: .ready,
            weather: nil
        )
    }

    /// Whether a mode id is configured (used to accept/reject a mode switch).
    public static func modeExists(_ id: String, configDirectory: URL) -> Bool {
        guard case let .valid(config) = ConfigValidator.validate(configDirectory: configDirectory) else {
            return false
        }
        return config.modes.contains { $0.id == id }
    }

    /// Orders modes by the canonical display order; any unlisted mode keeps its
    /// relative position after the known ones.
    private static func orderedModes(_ modes: [CerebralHelmModeConfig]) -> [CerebralHelmModeConfig] {
        modes.enumerated().sorted { lhs, rhs in
            let li = canonicalModeOrder.firstIndex(of: lhs.element.id) ?? (canonicalModeOrder.count + lhs.offset)
            let ri = canonicalModeOrder.firstIndex(of: rhs.element.id) ?? (canonicalModeOrder.count + rhs.offset)
            return li < ri
        }.map(\.element)
    }

    /// A mode config maps directly onto a mode view: the shared fields (id, label,
    /// theme, quick actions/apps, widgets, greeting, calendar/news profiles) line up,
    /// and the config-only fields (layout, extensions, project hints) are ignored.
    private static func modeView(_ config: CerebralHelmModeConfig) throws -> DashboardModeView {
        try JSONDecoder().decode(DashboardModeView.self, from: JSONEncoder().encode(config))
    }

    /// The active mode is the configured default. `Mode` raw values are the
    /// capitalized labels, so map the default id to its mode's label.
    private static func resolveMode(defaultID: String?, modes: [CerebralHelmModeConfig]) -> Mode {
        if let defaultID,
           let match = modes.first(where: { $0.id == defaultID }),
           let mode = Mode(rawValue: match.label) {
            return mode
        }
        return .executive
    }

    private static func idleHeimlich() -> DashboardHeimlich {
        // The chat/conversation surface was removed for the MVP (NIC-124); only the runtime
        // state remains on the center surface.
        DashboardHeimlich(state: .idle)
    }

    /// The honest pre-adapter regions: nothing is fabricated. Schedule and news are
    /// empty, system metrics and the mode widgets are unavailable.
    private static func degradedRegions() -> DashboardRegions {
        DashboardRegions(
            news: DashboardNewsRegion(emptyMessage: "News is unavailable.", headlines: [], state: .empty),
            schedule: DashboardScheduleRegion(emptyMessage: "No schedule yet.", items: [], state: .empty),
            systemHealth: DashboardSystemHealthRegion(
                battery: DashboardBatteryChannel(charging: nil, label: "Battery", percent: nil, pluggedIn: nil, state: .unavailable),
                cpuPercent: nil,
                memoryPercent: nil,
                network: nil,
                state: .unavailable
            ),
            widgets: DashboardRegionWidgets(
                dashboardRegionWidgetsLeft: unavailableWidget(),
                dashboardRegionWidgetsRight: unavailableWidget()
            )
        )
    }

    private static func unavailableWidget<T: WidgetEnvelope>() -> T {
        T(state: .unavailable)
    }
}

/// A minimal factory over the two structurally-identical widget envelopes so the
/// degraded left/right widgets can be built without duplicating their long inits.
protocol WidgetEnvelope {
    init(state: DashboardRegionState)
}

extension Left: WidgetEnvelope {
    init(state: DashboardRegionState) {
        self.init(action: nil, data: nil, emptyMessage: "Unavailable", freshness: nil, headline: nil, state: state, widgetID: "left")
    }
}

extension Right: WidgetEnvelope {
    init(state: DashboardRegionState) {
        self.init(action: nil, data: nil, emptyMessage: "Unavailable", freshness: nil, headline: nil, state: state, widgetID: "right")
    }
}
