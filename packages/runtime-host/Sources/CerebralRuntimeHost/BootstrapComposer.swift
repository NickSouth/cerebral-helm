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
        configDirectory: URL, activeModeID: String? = nil, systemMetricsExpected: Bool = false
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
            defaultModeID: defaultModeID, activeModeID: activeModeID,
            systemMetricsExpected: systemMetricsExpected
        )
    }

    /// Composes the bootstrap state through the layered ``ConfigLoader`` — the
    /// user-overrides read side (NIC-119c): pinned quick apps live in per-mode
    /// override files under the state root, so a workspace-aware surface must
    /// compose from the activated (merged) configuration, never the shipped
    /// defaults alone. A rejected candidate falls back to the last-known-good
    /// snapshot, then to the shipped defaults (FR-CFG-02).
    public static func compose(
        workspace: WorkspacePaths, activeModeID: String? = nil, systemMetricsExpected: Bool = false
    ) -> CerebralHelmBridgeBootstrapState {
        let active: ActiveConfig?
        switch ConfigLoader(workspace: workspace).load() {
        case let .activated(config):
            active = config
        case let .rejected(_, lastKnownGood):
            active = lastKnownGood
        }
        guard let active else {
            return compose(
                configDirectory: workspace.configDirectory, activeModeID: activeModeID,
                systemMetricsExpected: systemMetricsExpected
            )
        }
        return compose(
            modes: active.modes, agents: active.agents,
            defaultModeID: active.defaults.defaultModeID, activeModeID: activeModeID,
            systemMetricsExpected: systemMetricsExpected
        )
    }

    /// The single composition core: validated (possibly override-merged) configs in,
    /// bootstrap state out.
    private static func compose(
        modes modeConfigs: [CerebralHelmModeConfig],
        agents agentConfigs: [CerebralHelmAgentSurfaceConfig],
        defaultModeID: String?,
        activeModeID: String?,
        systemMetricsExpected: Bool = false
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
            regions: degradedRegions(systemMetricsExpected: systemMetricsExpected),
            schemaVersion: "1.0.0",
            summary: "Ready.",
            uiState: .ready,
            weather: nil
        )
    }

    /// The configured default mode id from the shipped defaults, or nil when the
    /// config is invalid. This is the "default mode" *setting* fallback (NIC-141) —
    /// distinct from the currently active mode, which restart-restore resolves
    /// separately.
    public static func defaultModeID(configDirectory: URL) -> String? {
        guard case let .valid(config) = ConfigValidator.validate(configDirectory: configDirectory) else {
            return nil
        }
        return config.defaults.defaultModeID
    }

    /// The configured default mode id through the layered ``ConfigLoader`` (user
    /// overrides, then last-known-good) — the workspace-aware counterpart, matching
    /// how ``compose(workspace:activeModeID:systemMetricsExpected:)`` sources it.
    public static func defaultModeID(workspace: WorkspacePaths) -> String? {
        switch ConfigLoader(workspace: workspace).load() {
        case let .activated(config):
            return config.defaults.defaultModeID
        case let .rejected(_, lastKnownGood):
            return lastKnownGood?.defaults.defaultModeID
        }
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
    /// empty, the mode widgets unavailable. System metrics render as loading (`.empty`)
    /// when their provider is available — a live sample is inbound, so the shell shows a
    /// same-shape skeleton rather than an "unavailable" flash on first paint / mode switch
    /// (NIC-136) — and as unavailable otherwise, staying honest on providerless builds.
    private static func degradedRegions(systemMetricsExpected: Bool = false) -> DashboardRegions {
        let systemHealthState: DashboardRegionState = systemMetricsExpected ? .empty : .unavailable
        return DashboardRegions(
            news: DashboardNewsRegion(emptyMessage: "News is unavailable.", headlines: [], state: .empty),
            schedule: DashboardScheduleRegion(emptyMessage: "No schedule yet.", items: [], state: .empty),
            systemHealth: DashboardSystemHealthRegion(
                battery: DashboardBatteryChannel(charging: nil, label: "Battery", percent: nil, pluggedIn: nil, state: systemHealthState),
                cpuPercent: nil,
                memoryPercent: nil,
                // No pressure level before the first live sample — the bar has no colour to take
                // yet, which is exactly what the skeleton state represents (NIC-158).
                memoryPressure: nil,
                network: nil,
                state: systemHealthState
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
