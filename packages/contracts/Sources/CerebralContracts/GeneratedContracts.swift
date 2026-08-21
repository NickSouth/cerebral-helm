// This file was generated from JSON Schema using quicktype, do not modify it directly.
// To parse the JSON, add this file to your project and do:
//
//   let cerebralHelmBridgeBootstrapState = try CerebralHelmBridgeBootstrapState(json)
//   let cerebralHelmBridgeCapabilityState = try CerebralHelmBridgeCapabilityState(json)
//   let cerebralHelmBridgeEvent = try CerebralHelmBridgeEvent(json)
//   let cerebralHelmBridgeHandshakeRequest = try CerebralHelmBridgeHandshakeRequest(json)
//   let cerebralHelmBridgeHandshakeResponse = try CerebralHelmBridgeHandshakeResponse(json)
//   let cerebralHelmBridgeOperationRequest = try CerebralHelmBridgeOperationRequest(json)
//   let cerebralHelmBridgeOperationResponse = try CerebralHelmBridgeOperationResponse(json)
//   let cerebralHelmSettingsSnapshot = try CerebralHelmSettingsSnapshot(json)
//   let cerebralHelmCommandEnvelope = try CerebralHelmCommandEnvelope(json)
//   let cerebralHelmCommandLifecycleEvent = try CerebralHelmCommandLifecycleEvent(json)
//   let cerebralHelmCommandTerminalResult = try CerebralHelmCommandTerminalResult(json)
//   let cerebralHelmStructuredError = try CerebralHelmStructuredError(json)
//   let cerebralHelmAgentSurfaceConfig = try CerebralHelmAgentSurfaceConfig(json)
//   let cerebralHelmApplicationDefaults = try CerebralHelmApplicationDefaults(json)
//   let cerebralHelmConfigValidationError = try CerebralHelmConfigValidationError(json)
//   let cerebralHelmModeOverride = try CerebralHelmModeOverride(json)
//   let cerebralHelmModeConfig = try CerebralHelmModeConfig(json)
//   let cerebralHelmModelProfileCatalog = try CerebralHelmModelProfileCatalog(json)
//   let cerebralHelmSettingsPatch = try CerebralHelmSettingsPatch(json)
//   let cerebralHelmNoteMetadata = try CerebralHelmNoteMetadata(json)
//   let cerebralHelmReferenceCatalog = try CerebralHelmReferenceCatalog(json)
//   let cerebralHelmReportDocument = try CerebralHelmReportDocument(json)
//   let cerebralHelmAppOpenInput = try CerebralHelmAppOpenInput(json)
//   let cerebralHelmAppOpenOutput = try CerebralHelmAppOpenOutput(json)
//   let cerebralHelmAppQuitInput = try CerebralHelmAppQuitInput(json)
//   let cerebralHelmAppQuitOutput = try CerebralHelmAppQuitOutput(json)
//   let cerebralHelmAppsListInput = try CerebralHelmAppsListInput(json)
//   let cerebralHelmAppsListOutput = try CerebralHelmAppsListOutput(json)
//   let cerebralHelmAppsQuitAllInput = try CerebralHelmAppsQuitAllInput(json)
//   let cerebralHelmAppsQuitAllOutput = try CerebralHelmAppsQuitAllOutput(json)
//   let cerebralHelmCalendarCreateEventInput = try CerebralHelmCalendarCreateEventInput(json)
//   let cerebralHelmCalendarCreateEventOutput = try CerebralHelmCalendarCreateEventOutput(json)
//   let cerebralHelmConfirmationDisclosure = try CerebralHelmConfirmationDisclosure(json)
//   let cerebralHelmCourseListInput = try CerebralHelmCourseListInput(json)
//   let cerebralHelmCourseListOutput = try CerebralHelmCourseListOutput(json)
//   let cerebralHelmCourseNoteCreateInput = try CerebralHelmCourseNoteCreateInput(json)
//   let cerebralHelmCourseNoteCreateOutput = try CerebralHelmCourseNoteCreateOutput(json)
//   let cerebralHelmGitCloneInput = try CerebralHelmGitCloneInput(json)
//   let cerebralHelmGitCloneOutput = try CerebralHelmGitCloneOutput(json)
//   let cerebralHelmGoogleSearchInput = try CerebralHelmGoogleSearchInput(json)
//   let cerebralHelmGoogleSearchOutput = try CerebralHelmGoogleSearchOutput(json)
//   let cerebralHelmHookRunInput = try CerebralHelmHookRunInput(json)
//   let cerebralHelmHookRunOutput = try CerebralHelmHookRunOutput(json)
//   let cerebralHelmLinearCreateIssueInput = try CerebralHelmLinearCreateIssueInput(json)
//   let cerebralHelmLinearCreateIssueOutput = try CerebralHelmLinearCreateIssueOutput(json)
//   let cerebralHelmMailOpenInput = try CerebralHelmMailOpenInput(json)
//   let cerebralHelmMailOpenOutput = try CerebralHelmMailOpenOutput(json)
//   let cerebralHelmMessagesSendInput = try CerebralHelmMessagesSendInput(json)
//   let cerebralHelmMessagesSendOutput = try CerebralHelmMessagesSendOutput(json)
//   let cerebralHelmModeApplyInput = try CerebralHelmModeApplyInput(json)
//   let cerebralHelmModeApplyOutput = try CerebralHelmModeApplyOutput(json)
//   let cerebralHelmNetworkSpeedTestInput = try CerebralHelmNetworkSpeedTestInput(json)
//   let cerebralHelmNetworkSpeedTestOutput = try CerebralHelmNetworkSpeedTestOutput(json)
//   let cerebralHelmNoteCaptureInput = try CerebralHelmNoteCaptureInput(json)
//   let cerebralHelmNoteCaptureOutput = try CerebralHelmNoteCaptureOutput(json)
//   let cerebralHelmNoteListInput = try CerebralHelmNoteListInput(json)
//   let cerebralHelmNoteListOutput = try CerebralHelmNoteListOutput(json)
//   let cerebralHelmNoteOpenInput = try CerebralHelmNoteOpenInput(json)
//   let cerebralHelmNoteOpenOutput = try CerebralHelmNoteOpenOutput(json)
//   let cerebralHelmNoteReadInput = try CerebralHelmNoteReadInput(json)
//   let cerebralHelmNoteReadOutput = try CerebralHelmNoteReadOutput(json)
//   let cerebralHelmNoteSearchInput = try CerebralHelmNoteSearchInput(json)
//   let cerebralHelmNoteSearchOutput = try CerebralHelmNoteSearchOutput(json)
//   let cerebralHelmProjectOpenInput = try CerebralHelmProjectOpenInput(json)
//   let cerebralHelmProjectOpenOutput = try CerebralHelmProjectOpenOutput(json)
//   let cerebralHelmProjectScaffoldInput = try CerebralHelmProjectScaffoldInput(json)
//   let cerebralHelmProjectScaffoldOutput = try CerebralHelmProjectScaffoldOutput(json)
//   let cerebralHelmSpotifyControlInput = try CerebralHelmSpotifyControlInput(json)
//   let cerebralHelmSpotifyControlOutput = try CerebralHelmSpotifyControlOutput(json)
//   let cerebralHelmSpotifyCreatePlaylistInput = try CerebralHelmSpotifyCreatePlaylistInput(json)
//   let cerebralHelmSpotifyCreatePlaylistOutput = try CerebralHelmSpotifyCreatePlaylistOutput(json)
//   let cerebralHelmSystemStatusReadInput = try CerebralHelmSystemStatusReadInput(json)
//   let cerebralHelmSystemStatusReadOutput = try CerebralHelmSystemStatusReadOutput(json)
//   let cerebralHelmToolDescriptor = try CerebralHelmToolDescriptor(json)
//   let cerebralHelmToolResult = try CerebralHelmToolResult(json)
//   let cerebralHelmURLOpenInput = try CerebralHelmURLOpenInput(json)
//   let cerebralHelmURLOpenOutput = try CerebralHelmURLOpenOutput(json)
//   let cerebralHelmWebOpenInput = try CerebralHelmWebOpenInput(json)
//   let cerebralHelmWebOpenOutput = try CerebralHelmWebOpenOutput(json)
//   let cerebralHelmWindowArrangeInput = try CerebralHelmWindowArrangeInput(json)
//   let cerebralHelmWindowArrangeOutput = try CerebralHelmWindowArrangeOutput(json)
//   let cerebralHelmYouTubeSearchInput = try CerebralHelmYouTubeSearchInput(json)
//   let cerebralHelmYouTubeSearchOutput = try CerebralHelmYouTubeSearchOutput(json)
//   let cerebralHelmWorkflowDefinition = try CerebralHelmWorkflowDefinition(json)

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

import Foundation

// MARK: - CerebralHelmBridgeBootstrapState
public struct CerebralHelmBridgeBootstrapState: Codable {
    /// The fixed global agent roster, identical in every mode (design spec §5.10). No add-agent
    /// capability.
    public let agents: [DashboardAgentSummary]
    public let commandsToday: Int
    /// The agent whose right-column-width workspace panel is open over the right column, or
    /// null. Defaults to null in every mode — Heimlich owns the center and nothing is expanded
    /// by default (design spec §5.10).
    public let expandedAgent: String?
    /// The center surface — Heimlich's consciousness — present in every mode; the center is
    /// never replaced (design spec §5.7). The chat/conversation overlay was removed for the MVP
    /// (NIC-124): conversing with Heimlich is post-MVP, so only the runtime `state` remains.
    public let heimlich: DashboardHeimlich
    public let mode: Mode
    /// All four resolved mode views, shipped eagerly so a mode switch re-themes instantly
    /// without a bridge round-trip or theme flash (NIC-117 d). The active mode is identified by
    /// the top-level `mode`.
    public let modes: [DashboardModeView]
    public let pendingConfirmations: Int
    public let project: String
    /// The active mode's region data (schedule, system health, news, left/right widgets). Heavy
    /// data is resolved on switch, not shipped eagerly for every mode.
    public let regions: DashboardRegions
    public let schemaVersion: String
    public let summary: String
    public let uiState: UIState
    /// Ambient weather for the persistent bottom bar. Optional (a Mac-only capability; mocked
    /// pre-Mac).
    public let weather: DashboardWeatherChannel?

    public init(agents: [DashboardAgentSummary], commandsToday: Int, expandedAgent: String?, heimlich: DashboardHeimlich, mode: Mode, modes: [DashboardModeView], pendingConfirmations: Int, project: String, regions: DashboardRegions, schemaVersion: String, summary: String, uiState: UIState, weather: DashboardWeatherChannel?) {
        self.agents = agents
        self.commandsToday = commandsToday
        self.expandedAgent = expandedAgent
        self.heimlich = heimlich
        self.mode = mode
        self.modes = modes
        self.pendingConfirmations = pendingConfirmations
        self.project = project
        self.regions = regions
        self.schemaVersion = schemaVersion
        self.summary = summary
        self.uiState = uiState
        self.weather = weather
    }
}

// MARK: CerebralHelmBridgeBootstrapState convenience initializers and mutators

public extension CerebralHelmBridgeBootstrapState {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CerebralHelmBridgeBootstrapState.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        agents: [DashboardAgentSummary]? = nil,
        commandsToday: Int? = nil,
        expandedAgent: String?? = nil,
        heimlich: DashboardHeimlich? = nil,
        mode: Mode? = nil,
        modes: [DashboardModeView]? = nil,
        pendingConfirmations: Int? = nil,
        project: String? = nil,
        regions: DashboardRegions? = nil,
        schemaVersion: String? = nil,
        summary: String? = nil,
        uiState: UIState? = nil,
        weather: DashboardWeatherChannel?? = nil
    ) -> CerebralHelmBridgeBootstrapState {
        return CerebralHelmBridgeBootstrapState(
            agents: agents ?? self.agents,
            commandsToday: commandsToday ?? self.commandsToday,
            expandedAgent: expandedAgent ?? self.expandedAgent,
            heimlich: heimlich ?? self.heimlich,
            mode: mode ?? self.mode,
            modes: modes ?? self.modes,
            pendingConfirmations: pendingConfirmations ?? self.pendingConfirmations,
            project: project ?? self.project,
            regions: regions ?? self.regions,
            schemaVersion: schemaVersion ?? self.schemaVersion,
            summary: summary ?? self.summary,
            uiState: uiState ?? self.uiState,
            weather: weather ?? self.weather
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - DashboardAgentSummary
public struct DashboardAgentSummary: Codable {
    /// The runtime dashboard status (design spec §5.10); event-driven, defaults to idle in
    /// bootstrap.
    public let activity: DashboardAgentActivity
    /// The configured availability flag (agent config `status`); not the runtime dashboard state.
    public let availability: DashboardAgentAvailability
    public let id, label, summary: String

    public init(activity: DashboardAgentActivity, availability: DashboardAgentAvailability, id: String, label: String, summary: String) {
        self.activity = activity
        self.availability = availability
        self.id = id
        self.label = label
        self.summary = summary
    }
}

// MARK: DashboardAgentSummary convenience initializers and mutators

public extension DashboardAgentSummary {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(DashboardAgentSummary.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        activity: DashboardAgentActivity? = nil,
        availability: DashboardAgentAvailability? = nil,
        id: String? = nil,
        label: String? = nil,
        summary: String? = nil
    ) -> DashboardAgentSummary {
        return DashboardAgentSummary(
            activity: activity ?? self.activity,
            availability: availability ?? self.availability,
            id: id ?? self.id,
            label: label ?? self.label,
            summary: summary ?? self.summary
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

/// The runtime dashboard status (design spec §5.10); event-driven, defaults to idle in
/// bootstrap.
public enum DashboardAgentActivity: String, Codable {
    case idle = "idle"
    case ready = "ready"
    case thinking = "thinking"
    case waiting = "waiting"
}

/// The configured availability flag (agent config `status`); not the runtime dashboard state.
public enum DashboardAgentAvailability: String, Codable {
    case disabled = "disabled"
    case enabled = "enabled"
    case mock = "mock"
    case unavailable = "unavailable"
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

/// The center surface — Heimlich's consciousness — present in every mode; the center is
/// never replaced (design spec §5.7). The chat/conversation overlay was removed for the MVP
/// (NIC-124): conversing with Heimlich is post-MVP, so only the runtime `state` remains.
// MARK: - DashboardHeimlich
public struct DashboardHeimlich: Codable {
    public let state: DashboardHeimlichState

    public init(state: DashboardHeimlichState) {
        self.state = state
    }
}

// MARK: DashboardHeimlich convenience initializers and mutators

public extension DashboardHeimlich {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(DashboardHeimlich.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        state: DashboardHeimlichState? = nil
    ) -> DashboardHeimlich {
        return DashboardHeimlich(
            state: state ?? self.state
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

public enum DashboardHeimlichState: String, Codable {
    case acting = "acting"
    case awaitingConfirmation = "awaiting_confirmation"
    case error = "error"
    case idle = "idle"
    case listening = "listening"
    case offline = "offline"
    case success = "success"
    case thinking = "thinking"
}

public enum Mode: String, Codable {
    case developer = "Developer"
    case entertainment = "Entertainment"
    case executive = "Executive"
    case school = "School"
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - DashboardModeView
public struct DashboardModeView: Codable {
    public let calendarProfile: String?
    public let greeting: DashboardModeGreeting?
    public let id, label: String
    public let newsProfile: String?
    /// Exactly 8 ordered slots; an id or null for an unconfigured slot (rendered as an honest
    /// disabled placeholder pre-wiring).
    public let quickActions: [String?]
    public let quickApps: [String]
    public let theme: DashboardModeTheme
    public let widgets: DashboardModeWidgets

    public init(calendarProfile: String?, greeting: DashboardModeGreeting?, id: String, label: String, newsProfile: String?, quickActions: [String?], quickApps: [String], theme: DashboardModeTheme, widgets: DashboardModeWidgets) {
        self.calendarProfile = calendarProfile
        self.greeting = greeting
        self.id = id
        self.label = label
        self.newsProfile = newsProfile
        self.quickActions = quickActions
        self.quickApps = quickApps
        self.theme = theme
        self.widgets = widgets
    }
}

// MARK: DashboardModeView convenience initializers and mutators

public extension DashboardModeView {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(DashboardModeView.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        calendarProfile: String?? = nil,
        greeting: DashboardModeGreeting?? = nil,
        id: String? = nil,
        label: String? = nil,
        newsProfile: String?? = nil,
        quickActions: [String?]? = nil,
        quickApps: [String]? = nil,
        theme: DashboardModeTheme? = nil,
        widgets: DashboardModeWidgets? = nil
    ) -> DashboardModeView {
        return DashboardModeView(
            calendarProfile: calendarProfile ?? self.calendarProfile,
            greeting: greeting ?? self.greeting,
            id: id ?? self.id,
            label: label ?? self.label,
            newsProfile: newsProfile ?? self.newsProfile,
            quickActions: quickActions ?? self.quickActions,
            quickApps: quickApps ?? self.quickApps,
            theme: theme ?? self.theme,
            widgets: widgets ?? self.widgets
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - DashboardModeGreeting
public struct DashboardModeGreeting: Codable {
    public let directive: String?
    public let fallback, persona: String

    public init(directive: String?, fallback: String, persona: String) {
        self.directive = directive
        self.fallback = fallback
        self.persona = persona
    }
}

// MARK: DashboardModeGreeting convenience initializers and mutators

public extension DashboardModeGreeting {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(DashboardModeGreeting.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        directive: String?? = nil,
        fallback: String? = nil,
        persona: String? = nil
    ) -> DashboardModeGreeting {
        return DashboardModeGreeting(
            directive: directive ?? self.directive,
            fallback: fallback ?? self.fallback,
            persona: persona ?? self.persona
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - DashboardModeTheme
public struct DashboardModeTheme: Codable {
    public let accentPrimary, accentSecondary: String

    public init(accentPrimary: String, accentSecondary: String) {
        self.accentPrimary = accentPrimary
        self.accentSecondary = accentSecondary
    }
}

// MARK: DashboardModeTheme convenience initializers and mutators

public extension DashboardModeTheme {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(DashboardModeTheme.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        accentPrimary: String? = nil,
        accentSecondary: String? = nil
    ) -> DashboardModeTheme {
        return DashboardModeTheme(
            accentPrimary: accentPrimary ?? self.accentPrimary,
            accentSecondary: accentSecondary ?? self.accentSecondary
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - DashboardModeWidgets
public struct DashboardModeWidgets: Codable {
    public let dashboardModeWidgetsLeft, dashboardModeWidgetsRight: String

    public enum CodingKeys: String, CodingKey {
        case dashboardModeWidgetsLeft = "left"
        case dashboardModeWidgetsRight = "right"
    }

    public init(dashboardModeWidgetsLeft: String, dashboardModeWidgetsRight: String) {
        self.dashboardModeWidgetsLeft = dashboardModeWidgetsLeft
        self.dashboardModeWidgetsRight = dashboardModeWidgetsRight
    }
}

// MARK: DashboardModeWidgets convenience initializers and mutators

public extension DashboardModeWidgets {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(DashboardModeWidgets.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        dashboardModeWidgetsLeft: String? = nil,
        dashboardModeWidgetsRight: String? = nil
    ) -> DashboardModeWidgets {
        return DashboardModeWidgets(
            dashboardModeWidgetsLeft: dashboardModeWidgetsLeft ?? self.dashboardModeWidgetsLeft,
            dashboardModeWidgetsRight: dashboardModeWidgetsRight ?? self.dashboardModeWidgetsRight
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

/// The active mode's region data (schedule, system health, news, left/right widgets). Heavy
/// data is resolved on switch, not shipped eagerly for every mode.
// MARK: - DashboardRegions
public struct DashboardRegions: Codable {
    public let news: DashboardNewsRegion
    public let schedule: DashboardScheduleRegion
    public let systemHealth: DashboardSystemHealthRegion
    public let widgets: DashboardRegionWidgets

    public init(news: DashboardNewsRegion, schedule: DashboardScheduleRegion, systemHealth: DashboardSystemHealthRegion, widgets: DashboardRegionWidgets) {
        self.news = news
        self.schedule = schedule
        self.systemHealth = systemHealth
        self.widgets = widgets
    }
}

// MARK: DashboardRegions convenience initializers and mutators

public extension DashboardRegions {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(DashboardRegions.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        news: DashboardNewsRegion? = nil,
        schedule: DashboardScheduleRegion? = nil,
        systemHealth: DashboardSystemHealthRegion? = nil,
        widgets: DashboardRegionWidgets? = nil
    ) -> DashboardRegions {
        return DashboardRegions(
            news: news ?? self.news,
            schedule: schedule ?? self.schedule,
            systemHealth: systemHealth ?? self.systemHealth,
            widgets: widgets ?? self.widgets
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - DashboardNewsRegion
public struct DashboardNewsRegion: Codable {
    public let emptyMessage: String?
    public let headlines: [DashboardNewsHeadline]
    public let state: DashboardRegionState

    public init(emptyMessage: String?, headlines: [DashboardNewsHeadline], state: DashboardRegionState) {
        self.emptyMessage = emptyMessage
        self.headlines = headlines
        self.state = state
    }
}

// MARK: DashboardNewsRegion convenience initializers and mutators

public extension DashboardNewsRegion {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(DashboardNewsRegion.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        emptyMessage: String?? = nil,
        headlines: [DashboardNewsHeadline]? = nil,
        state: DashboardRegionState? = nil
    ) -> DashboardNewsRegion {
        return DashboardNewsRegion(
            emptyMessage: emptyMessage ?? self.emptyMessage,
            headlines: headlines ?? self.headlines,
            state: state ?? self.state
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - DashboardNewsHeadline
public struct DashboardNewsHeadline: Codable {
    public let id, source, title: String
    /// The article's navigable destination (design spec §5.4), opened on click via the web.open
    /// tool. Optional — omitted (never fabricated) when the source has no link, in which case
    /// the headline renders as non-interactive text.
    public let url: String?

    public init(id: String, source: String, title: String, url: String?) {
        self.id = id
        self.source = source
        self.title = title
        self.url = url
    }
}

// MARK: DashboardNewsHeadline convenience initializers and mutators

public extension DashboardNewsHeadline {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(DashboardNewsHeadline.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        id: String? = nil,
        source: String? = nil,
        title: String? = nil,
        url: String?? = nil
    ) -> DashboardNewsHeadline {
        return DashboardNewsHeadline(
            id: id ?? self.id,
            source: source ?? self.source,
            title: title ?? self.title,
            url: url ?? self.url
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

public enum DashboardRegionState: String, Codable {
    case empty = "empty"
    case ready = "ready"
    case stale = "stale"
    case unavailable = "unavailable"
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - DashboardScheduleRegion
public struct DashboardScheduleRegion: Codable {
    public let emptyMessage: String?
    public let items: [DashboardScheduleItem]
    public let state: DashboardRegionState

    public init(emptyMessage: String?, items: [DashboardScheduleItem], state: DashboardRegionState) {
        self.emptyMessage = emptyMessage
        self.items = items
        self.state = state
    }
}

// MARK: DashboardScheduleRegion convenience initializers and mutators

public extension DashboardScheduleRegion {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(DashboardScheduleRegion.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        emptyMessage: String?? = nil,
        items: [DashboardScheduleItem]? = nil,
        state: DashboardRegionState? = nil
    ) -> DashboardScheduleRegion {
        return DashboardScheduleRegion(
            emptyMessage: emptyMessage ?? self.emptyMessage,
            items: items ?? self.items,
            state: state ?? self.state
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - DashboardScheduleItem
public struct DashboardScheduleItem: Codable {
    public let id: String
    public let kind: DashboardScheduleKind
    public let location, start: String?
    public let title: String

    public init(id: String, kind: DashboardScheduleKind, location: String?, start: String?, title: String) {
        self.id = id
        self.kind = kind
        self.location = location
        self.start = start
        self.title = title
    }
}

// MARK: DashboardScheduleItem convenience initializers and mutators

public extension DashboardScheduleItem {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(DashboardScheduleItem.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        id: String? = nil,
        kind: DashboardScheduleKind? = nil,
        location: String?? = nil,
        start: String?? = nil,
        title: String? = nil
    ) -> DashboardScheduleItem {
        return DashboardScheduleItem(
            id: id ?? self.id,
            kind: kind ?? self.kind,
            location: location ?? self.location,
            start: start ?? self.start,
            title: title ?? self.title
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

public enum DashboardScheduleKind: String, Codable {
    case today = "today"
    case tonight = "tonight"
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - DashboardSystemHealthRegion
public struct DashboardSystemHealthRegion: Codable {
    public let battery: DashboardBatteryChannel
    /// CPU load 0–100 as a fraction of total machine capacity, TIME-AVERAGED over roughly the
    /// last 30 seconds — not an instantaneous reading (NIC-158). What matters for heat, fan,
    /// battery, and responsiveness is sustained load, so the streamed value is smoothed: a brief
    /// spike barely moves it, while genuinely sustained load climbs into it. Consumers should
    /// treat a high value as 'this has been going on for a while'. The one-shot
    /// `system.status.read` tool reports the instantaneous figure instead. Note the value is
    /// normalized across all logical cores, so one saturated core reads far lower on a many-core
    /// machine than on a small one.
    public let cpuPercent: Double?
    /// Memory used as a percentage of physical RAM (Activity Monitor's 'Memory Used'), lightly
    /// time-averaged (~10s) so the bar glides rather than jumps. This is NOT a strain signal:
    /// macOS deliberately keeps RAM full of cache, so a healthy machine sits near 100% — read
    /// `memoryPressure` for whether memory is actually under pressure.
    public let memoryPercent: Double?
    /// macOS's own memory-pressure level, read from `kern.memorystatus_vm_pressure_level` — the
    /// same signal the public dispatch memory-pressure source reports. Distinct from
    /// `memoryPercent`, and the honest basis for the memory bar's colour: on a modern Mac the
    /// used/total ratio sits near 100% permanently (the OS deliberately fills RAM with cache),
    /// so it says nothing about whether memory is actually under strain. Absent when the level
    /// cannot be sampled (non-macOS host, or an unrecognized value from a future OS), in which
    /// case consumers fall back to thresholding `memoryPercent` rather than guessing a level.
    public let memoryPressure: DashboardMemoryPressure?
    public let network: DashboardNetworkChannel?
    public let state: DashboardRegionState

    public init(battery: DashboardBatteryChannel, cpuPercent: Double?, memoryPercent: Double?, memoryPressure: DashboardMemoryPressure?, network: DashboardNetworkChannel?, state: DashboardRegionState) {
        self.battery = battery
        self.cpuPercent = cpuPercent
        self.memoryPercent = memoryPercent
        self.memoryPressure = memoryPressure
        self.network = network
        self.state = state
    }
}

// MARK: DashboardSystemHealthRegion convenience initializers and mutators

public extension DashboardSystemHealthRegion {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(DashboardSystemHealthRegion.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        battery: DashboardBatteryChannel? = nil,
        cpuPercent: Double?? = nil,
        memoryPercent: Double?? = nil,
        memoryPressure: DashboardMemoryPressure?? = nil,
        network: DashboardNetworkChannel?? = nil,
        state: DashboardRegionState? = nil
    ) -> DashboardSystemHealthRegion {
        return DashboardSystemHealthRegion(
            battery: battery ?? self.battery,
            cpuPercent: cpuPercent ?? self.cpuPercent,
            memoryPercent: memoryPercent ?? self.memoryPercent,
            memoryPressure: memoryPressure ?? self.memoryPressure,
            network: network ?? self.network,
            state: state ?? self.state
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - DashboardBatteryChannel
public struct DashboardBatteryChannel: Codable {
    /// Whether the battery is currently charging, when known (Mac-only capability).
    public let charging: Bool?
    public let label: String
    /// Charge level 0–100, when known (Mac-only capability).
    public let percent: Double?
    /// Whether the machine is on external power, when known (a full battery on AC is plugged in
    /// but not charging).
    public let pluggedIn: Bool?
    public let state: DashboardRegionState

    public init(charging: Bool?, label: String, percent: Double?, pluggedIn: Bool?, state: DashboardRegionState) {
        self.charging = charging
        self.label = label
        self.percent = percent
        self.pluggedIn = pluggedIn
        self.state = state
    }
}

// MARK: DashboardBatteryChannel convenience initializers and mutators

public extension DashboardBatteryChannel {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(DashboardBatteryChannel.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        charging: Bool?? = nil,
        label: String? = nil,
        percent: Double?? = nil,
        pluggedIn: Bool?? = nil,
        state: DashboardRegionState? = nil
    ) -> DashboardBatteryChannel {
        return DashboardBatteryChannel(
            charging: charging ?? self.charging,
            label: label ?? self.label,
            percent: percent ?? self.percent,
            pluggedIn: pluggedIn ?? self.pluggedIn,
            state: state ?? self.state
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

/// macOS's own memory-pressure level, read from `kern.memorystatus_vm_pressure_level` — the
/// same signal the public dispatch memory-pressure source reports. Distinct from
/// `memoryPercent`, and the honest basis for the memory bar's colour: on a modern Mac the
/// used/total ratio sits near 100% permanently (the OS deliberately fills RAM with cache),
/// so it says nothing about whether memory is actually under strain. Absent when the level
/// cannot be sampled (non-macOS host, or an unrecognized value from a future OS), in which
/// case consumers fall back to thresholding `memoryPercent` rather than guessing a level.
public enum DashboardMemoryPressure: String, Codable {
    case critical = "critical"
    case normal = "normal"
    case warn = "warn"
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - DashboardNetworkChannel
public struct DashboardNetworkChannel: Codable {
    public let label: String
    /// Wi-Fi link (transmit) rate in Mbps — the connection's speed, when known.
    public let linkMbps: Double?
    /// Wi-Fi signal strength in dBm (a negative number; closer to zero is stronger), when the
    /// radio is on and associated.
    public let signalRssi: Double?
    public let state: DashboardRegionState
    /// Wi-Fi radio state: powered on, switched off by the user, or no Wi-Fi interface on this
    /// machine. Absent and off are distinct — a Mac with no Wi-Fi hardware is not a Mac whose
    /// radio the user turned off.
    public let wifiPower: DashboardWiFiPower?

    public init(label: String, linkMbps: Double?, signalRssi: Double?, state: DashboardRegionState, wifiPower: DashboardWiFiPower?) {
        self.label = label
        self.linkMbps = linkMbps
        self.signalRssi = signalRssi
        self.state = state
        self.wifiPower = wifiPower
    }
}

// MARK: DashboardNetworkChannel convenience initializers and mutators

public extension DashboardNetworkChannel {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(DashboardNetworkChannel.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        label: String? = nil,
        linkMbps: Double?? = nil,
        signalRssi: Double?? = nil,
        state: DashboardRegionState? = nil,
        wifiPower: DashboardWiFiPower?? = nil
    ) -> DashboardNetworkChannel {
        return DashboardNetworkChannel(
            label: label ?? self.label,
            linkMbps: linkMbps ?? self.linkMbps,
            signalRssi: signalRssi ?? self.signalRssi,
            state: state ?? self.state,
            wifiPower: wifiPower ?? self.wifiPower
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

/// Wi-Fi radio state: powered on, switched off by the user, or no Wi-Fi interface on this
/// machine. Absent and off are distinct — a Mac with no Wi-Fi hardware is not a Mac whose
/// radio the user turned off.
public enum DashboardWiFiPower: String, Codable {
    case absent = "absent"
    case off = "off"
    case on = "on"
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - DashboardRegionWidgets
public struct DashboardRegionWidgets: Codable {
    /// The common widget-data envelope (mirrors apps/dashboard/src/widgets/widgetData.ts). The
    /// per-widget payload is the open `data` object.
    public let dashboardRegionWidgetsLeft: Left
    /// The common widget-data envelope (mirrors apps/dashboard/src/widgets/widgetData.ts). The
    /// per-widget payload is the open `data` object.
    public let dashboardRegionWidgetsRight: Right

    public enum CodingKeys: String, CodingKey {
        case dashboardRegionWidgetsLeft = "left"
        case dashboardRegionWidgetsRight = "right"
    }

    public init(dashboardRegionWidgetsLeft: Left, dashboardRegionWidgetsRight: Right) {
        self.dashboardRegionWidgetsLeft = dashboardRegionWidgetsLeft
        self.dashboardRegionWidgetsRight = dashboardRegionWidgetsRight
    }
}

// MARK: DashboardRegionWidgets convenience initializers and mutators

public extension DashboardRegionWidgets {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(DashboardRegionWidgets.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        dashboardRegionWidgetsLeft: Left? = nil,
        dashboardRegionWidgetsRight: Right? = nil
    ) -> DashboardRegionWidgets {
        return DashboardRegionWidgets(
            dashboardRegionWidgetsLeft: dashboardRegionWidgetsLeft ?? self.dashboardRegionWidgetsLeft,
            dashboardRegionWidgetsRight: dashboardRegionWidgetsRight ?? self.dashboardRegionWidgetsRight
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

/// The common widget-data envelope (mirrors apps/dashboard/src/widgets/widgetData.ts). The
/// per-widget payload is the open `data` object.
// MARK: - Left
public struct Left: Codable {
    public let action: LeftAction?
    public let data: [String: JSONAny]?
    public let emptyMessage: String?
    public let freshness: LeftFreshness?
    public let headline: String?
    public let state: DashboardRegionState
    public let widgetID: String

    public enum CodingKeys: String, CodingKey {
        case action, data, emptyMessage, freshness, headline, state
        case widgetID = "widgetId"
    }

    public init(action: LeftAction?, data: [String: JSONAny]?, emptyMessage: String?, freshness: LeftFreshness?, headline: String?, state: DashboardRegionState, widgetID: String) {
        self.action = action
        self.data = data
        self.emptyMessage = emptyMessage
        self.freshness = freshness
        self.headline = headline
        self.state = state
        self.widgetID = widgetID
    }
}

// MARK: Left convenience initializers and mutators

public extension Left {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(Left.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        action: LeftAction?? = nil,
        data: [String: JSONAny]?? = nil,
        emptyMessage: String?? = nil,
        freshness: LeftFreshness?? = nil,
        headline: String?? = nil,
        state: DashboardRegionState? = nil,
        widgetID: String? = nil
    ) -> Left {
        return Left(
            action: action ?? self.action,
            data: data ?? self.data,
            emptyMessage: emptyMessage ?? self.emptyMessage,
            freshness: freshness ?? self.freshness,
            headline: headline ?? self.headline,
            state: state ?? self.state,
            widgetID: widgetID ?? self.widgetID
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - LeftAction
public struct LeftAction: Codable {
    public let id, label: String

    public init(id: String, label: String) {
        self.id = id
        self.label = label
    }
}

// MARK: LeftAction convenience initializers and mutators

public extension LeftAction {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(LeftAction.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        id: String? = nil,
        label: String? = nil
    ) -> LeftAction {
        return LeftAction(
            id: id ?? self.id,
            label: label ?? self.label
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - LeftFreshness
public struct LeftFreshness: Codable {
    public let label, observedAt: String

    public init(label: String, observedAt: String) {
        self.label = label
        self.observedAt = observedAt
    }
}

// MARK: LeftFreshness convenience initializers and mutators

public extension LeftFreshness {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(LeftFreshness.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        label: String? = nil,
        observedAt: String? = nil
    ) -> LeftFreshness {
        return LeftFreshness(
            label: label ?? self.label,
            observedAt: observedAt ?? self.observedAt
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

/// The common widget-data envelope (mirrors apps/dashboard/src/widgets/widgetData.ts). The
/// per-widget payload is the open `data` object.
// MARK: - Right
public struct Right: Codable {
    public let action: RightAction?
    public let data: [String: JSONAny]?
    public let emptyMessage: String?
    public let freshness: RightFreshness?
    public let headline: String?
    public let state: DashboardRegionState
    public let widgetID: String

    public enum CodingKeys: String, CodingKey {
        case action, data, emptyMessage, freshness, headline, state
        case widgetID = "widgetId"
    }

    public init(action: RightAction?, data: [String: JSONAny]?, emptyMessage: String?, freshness: RightFreshness?, headline: String?, state: DashboardRegionState, widgetID: String) {
        self.action = action
        self.data = data
        self.emptyMessage = emptyMessage
        self.freshness = freshness
        self.headline = headline
        self.state = state
        self.widgetID = widgetID
    }
}

// MARK: Right convenience initializers and mutators

public extension Right {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(Right.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        action: RightAction?? = nil,
        data: [String: JSONAny]?? = nil,
        emptyMessage: String?? = nil,
        freshness: RightFreshness?? = nil,
        headline: String?? = nil,
        state: DashboardRegionState? = nil,
        widgetID: String? = nil
    ) -> Right {
        return Right(
            action: action ?? self.action,
            data: data ?? self.data,
            emptyMessage: emptyMessage ?? self.emptyMessage,
            freshness: freshness ?? self.freshness,
            headline: headline ?? self.headline,
            state: state ?? self.state,
            widgetID: widgetID ?? self.widgetID
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - RightAction
public struct RightAction: Codable {
    public let id, label: String

    public init(id: String, label: String) {
        self.id = id
        self.label = label
    }
}

// MARK: RightAction convenience initializers and mutators

public extension RightAction {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(RightAction.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        id: String? = nil,
        label: String? = nil
    ) -> RightAction {
        return RightAction(
            id: id ?? self.id,
            label: label ?? self.label
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - RightFreshness
public struct RightFreshness: Codable {
    public let label, observedAt: String

    public init(label: String, observedAt: String) {
        self.label = label
        self.observedAt = observedAt
    }
}

// MARK: RightFreshness convenience initializers and mutators

public extension RightFreshness {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(RightFreshness.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        label: String? = nil,
        observedAt: String? = nil
    ) -> RightFreshness {
        return RightFreshness(
            label: label ?? self.label,
            observedAt: observedAt ?? self.observedAt
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

public enum UIState: String, Codable {
    case cancelled = "cancelled"
    case confirmation = "confirmation"
    case empty = "empty"
    case error = "error"
    case loading = "loading"
    case offline = "offline"
    case ready = "ready"
    case stale = "stale"
    case success = "success"
    case unavailable = "unavailable"
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

/// Ambient weather for the persistent bottom bar. Optional (a Mac-only capability; mocked
/// pre-Mac).
// MARK: - DashboardWeatherChannel
public struct DashboardWeatherChannel: Codable {
    /// Short condition phrase, e.g. "Partly Cloudy".
    public let condition: String?
    public let label: String
    public let state: DashboardRegionState
    /// Temperature in °F, when known.
    public let temperatureF: Double?

    public init(condition: String?, label: String, state: DashboardRegionState, temperatureF: Double?) {
        self.condition = condition
        self.label = label
        self.state = state
        self.temperatureF = temperatureF
    }
}

// MARK: DashboardWeatherChannel convenience initializers and mutators

public extension DashboardWeatherChannel {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(DashboardWeatherChannel.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        condition: String?? = nil,
        label: String? = nil,
        state: DashboardRegionState? = nil,
        temperatureF: Double?? = nil
    ) -> DashboardWeatherChannel {
        return DashboardWeatherChannel(
            condition: condition ?? self.condition,
            label: label ?? self.label,
            state: state ?? self.state,
            temperatureF: temperatureF ?? self.temperatureF
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - CerebralHelmBridgeCapabilityState
public struct CerebralHelmBridgeCapabilityState: Codable {
    public let available: Bool
    public let degradedReason: String?
    public let id: String
    public let source: CerebralHelmBridgeCapabilityStateSource

    public init(available: Bool, degradedReason: String?, id: String, source: CerebralHelmBridgeCapabilityStateSource) {
        self.available = available
        self.degradedReason = degradedReason
        self.id = id
        self.source = source
    }
}

// MARK: CerebralHelmBridgeCapabilityState convenience initializers and mutators

public extension CerebralHelmBridgeCapabilityState {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CerebralHelmBridgeCapabilityState.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        available: Bool? = nil,
        degradedReason: String?? = nil,
        id: String? = nil,
        source: CerebralHelmBridgeCapabilityStateSource? = nil
    ) -> CerebralHelmBridgeCapabilityState {
        return CerebralHelmBridgeCapabilityState(
            available: available ?? self.available,
            degradedReason: degradedReason ?? self.degradedReason,
            id: id ?? self.id,
            source: source ?? self.source
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

public enum CerebralHelmBridgeCapabilityStateSource: String, Codable {
    case mock = "mock"
    case native = "native"
    case unavailable = "unavailable"
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - CerebralHelmBridgeEvent
public struct CerebralHelmBridgeEvent: Codable {
    public let eventID: String
    public let payload: [String: JSONAny]
    public let schemaVersion: String
    public let timestamp: Date
    public let type: CerebralHelmBridgeEventType

    public enum CodingKeys: String, CodingKey {
        case eventID = "eventId"
        case payload, schemaVersion, timestamp, type
    }

    public init(eventID: String, payload: [String: JSONAny], schemaVersion: String, timestamp: Date, type: CerebralHelmBridgeEventType) {
        self.eventID = eventID
        self.payload = payload
        self.schemaVersion = schemaVersion
        self.timestamp = timestamp
        self.type = type
    }
}

// MARK: CerebralHelmBridgeEvent convenience initializers and mutators

public extension CerebralHelmBridgeEvent {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CerebralHelmBridgeEvent.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        eventID: String? = nil,
        payload: [String: JSONAny]? = nil,
        schemaVersion: String? = nil,
        timestamp: Date? = nil,
        type: CerebralHelmBridgeEventType? = nil
    ) -> CerebralHelmBridgeEvent {
        return CerebralHelmBridgeEvent(
            eventID: eventID ?? self.eventID,
            payload: payload ?? self.payload,
            schemaVersion: schemaVersion ?? self.schemaVersion,
            timestamp: timestamp ?? self.timestamp,
            type: type ?? self.type
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

public enum CerebralHelmBridgeEventType: String, Codable {
    case appsChanged = "apps.changed"
    case bridgeCapabilityChanged = "bridge.capability.changed"
    case commandLifecycleTransition = "command.lifecycle.transition"
    case configChanged = "config.changed"
    case confirmationChanged = "confirmation.changed"
    case displayTopologyChanged = "display.topology.changed"
    case layoutSessionChanged = "layout.session.changed"
    case mailChanged = "mail.changed"
    case modeQuickappsChanged = "mode.quickapps.changed"
    case modeWindowcollapseChanged = "mode.windowcollapse.changed"
    case newsChanged = "news.changed"
    case scheduleChanged = "schedule.changed"
    case settingsChanged = "settings.changed"
    case systemChecksChanged = "system.checks.changed"
    case systemStatusChanged = "system.status.changed"
    case weatherChanged = "weather.changed"
    case widgetDataChanged = "widget.data.changed"
    case workflowActionProgress = "workflow.action.progress"
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - CerebralHelmBridgeHandshakeRequest
public struct CerebralHelmBridgeHandshakeRequest: Codable {
    public let messageID: String
    public let schemaVersion: String
    public let supportedBridgeMajor, supportedBridgeMinorFloor: Int
    public let type: CerebralHelmBridgeHandshakeRequestType
    public let uiVersion: String

    public enum CodingKeys: String, CodingKey {
        case messageID = "messageId"
        case schemaVersion, supportedBridgeMajor, supportedBridgeMinorFloor, type, uiVersion
    }

    public init(messageID: String, schemaVersion: String, supportedBridgeMajor: Int, supportedBridgeMinorFloor: Int, type: CerebralHelmBridgeHandshakeRequestType, uiVersion: String) {
        self.messageID = messageID
        self.schemaVersion = schemaVersion
        self.supportedBridgeMajor = supportedBridgeMajor
        self.supportedBridgeMinorFloor = supportedBridgeMinorFloor
        self.type = type
        self.uiVersion = uiVersion
    }
}

// MARK: CerebralHelmBridgeHandshakeRequest convenience initializers and mutators

public extension CerebralHelmBridgeHandshakeRequest {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CerebralHelmBridgeHandshakeRequest.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        messageID: String? = nil,
        schemaVersion: String? = nil,
        supportedBridgeMajor: Int? = nil,
        supportedBridgeMinorFloor: Int? = nil,
        type: CerebralHelmBridgeHandshakeRequestType? = nil,
        uiVersion: String? = nil
    ) -> CerebralHelmBridgeHandshakeRequest {
        return CerebralHelmBridgeHandshakeRequest(
            messageID: messageID ?? self.messageID,
            schemaVersion: schemaVersion ?? self.schemaVersion,
            supportedBridgeMajor: supportedBridgeMajor ?? self.supportedBridgeMajor,
            supportedBridgeMinorFloor: supportedBridgeMinorFloor ?? self.supportedBridgeMinorFloor,
            type: type ?? self.type,
            uiVersion: uiVersion ?? self.uiVersion
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

public enum CerebralHelmBridgeHandshakeRequestType: String, Codable {
    case bridgeHandshakeRequest = "bridge.handshake.request"
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - CerebralHelmBridgeHandshakeResponse
public struct CerebralHelmBridgeHandshakeResponse: Codable {
    public let bridgeVersion: String
    public let capabilities: [Capability]
    public let compatible: Bool
    public let coreVersion: String
    public let degradedFeatures: [DegradedFeature]
    public let messageID: String
    public let recovery: Recovery?
    public let schemaVersion: String
    public let startupMode: StartupMode
    public let transport: Transport
    public let type: CerebralHelmBridgeHandshakeResponseType
    public let uiVersion: String

    public enum CodingKeys: String, CodingKey {
        case bridgeVersion, capabilities, compatible, coreVersion, degradedFeatures
        case messageID = "messageId"
        case recovery, schemaVersion, startupMode, transport, type, uiVersion
    }

    public init(bridgeVersion: String, capabilities: [Capability], compatible: Bool, coreVersion: String, degradedFeatures: [DegradedFeature], messageID: String, recovery: Recovery?, schemaVersion: String, startupMode: StartupMode, transport: Transport, type: CerebralHelmBridgeHandshakeResponseType, uiVersion: String) {
        self.bridgeVersion = bridgeVersion
        self.capabilities = capabilities
        self.compatible = compatible
        self.coreVersion = coreVersion
        self.degradedFeatures = degradedFeatures
        self.messageID = messageID
        self.recovery = recovery
        self.schemaVersion = schemaVersion
        self.startupMode = startupMode
        self.transport = transport
        self.type = type
        self.uiVersion = uiVersion
    }
}

// MARK: CerebralHelmBridgeHandshakeResponse convenience initializers and mutators

public extension CerebralHelmBridgeHandshakeResponse {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CerebralHelmBridgeHandshakeResponse.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        bridgeVersion: String? = nil,
        capabilities: [Capability]? = nil,
        compatible: Bool? = nil,
        coreVersion: String? = nil,
        degradedFeatures: [DegradedFeature]? = nil,
        messageID: String? = nil,
        recovery: Recovery?? = nil,
        schemaVersion: String? = nil,
        startupMode: StartupMode? = nil,
        transport: Transport? = nil,
        type: CerebralHelmBridgeHandshakeResponseType? = nil,
        uiVersion: String? = nil
    ) -> CerebralHelmBridgeHandshakeResponse {
        return CerebralHelmBridgeHandshakeResponse(
            bridgeVersion: bridgeVersion ?? self.bridgeVersion,
            capabilities: capabilities ?? self.capabilities,
            compatible: compatible ?? self.compatible,
            coreVersion: coreVersion ?? self.coreVersion,
            degradedFeatures: degradedFeatures ?? self.degradedFeatures,
            messageID: messageID ?? self.messageID,
            recovery: recovery ?? self.recovery,
            schemaVersion: schemaVersion ?? self.schemaVersion,
            startupMode: startupMode ?? self.startupMode,
            transport: transport ?? self.transport,
            type: type ?? self.type,
            uiVersion: uiVersion ?? self.uiVersion
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - Capability
public struct Capability: Codable {
    public let available: Bool
    public let degradedReason: String?
    public let id: String
    public let source: CerebralHelmBridgeCapabilityStateSource

    public init(available: Bool, degradedReason: String?, id: String, source: CerebralHelmBridgeCapabilityStateSource) {
        self.available = available
        self.degradedReason = degradedReason
        self.id = id
        self.source = source
    }
}

// MARK: Capability convenience initializers and mutators

public extension Capability {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(Capability.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        available: Bool? = nil,
        degradedReason: String?? = nil,
        id: String? = nil,
        source: CerebralHelmBridgeCapabilityStateSource? = nil
    ) -> Capability {
        return Capability(
            available: available ?? self.available,
            degradedReason: degradedReason ?? self.degradedReason,
            id: id ?? self.id,
            source: source ?? self.source
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - DegradedFeature
public struct DegradedFeature: Codable {
    public let fallbackUIState: FallbackUIState
    public let id: String
    public let reason: String

    public enum CodingKeys: String, CodingKey {
        case fallbackUIState = "fallbackUiState"
        case id, reason
    }

    public init(fallbackUIState: FallbackUIState, id: String, reason: String) {
        self.fallbackUIState = fallbackUIState
        self.id = id
        self.reason = reason
    }
}

// MARK: DegradedFeature convenience initializers and mutators

public extension DegradedFeature {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(DegradedFeature.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        fallbackUIState: FallbackUIState? = nil,
        id: String? = nil,
        reason: String? = nil
    ) -> DegradedFeature {
        return DegradedFeature(
            fallbackUIState: fallbackUIState ?? self.fallbackUIState,
            id: id ?? self.id,
            reason: reason ?? self.reason
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

public enum FallbackUIState: String, Codable {
    case error = "error"
    case offline = "offline"
    case stale = "stale"
    case unavailable = "unavailable"
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - Recovery
public struct Recovery: Codable {
    public let diagnosticCode: String
    public let readOnly: Bool
    public let reason: Reason
    public let remediation: String

    public init(diagnosticCode: String, readOnly: Bool, reason: Reason, remediation: String) {
        self.diagnosticCode = diagnosticCode
        self.readOnly = readOnly
        self.reason = reason
        self.remediation = remediation
    }
}

// MARK: Recovery convenience initializers and mutators

public extension Recovery {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(Recovery.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        diagnosticCode: String? = nil,
        readOnly: Bool? = nil,
        reason: Reason? = nil,
        remediation: String? = nil
    ) -> Recovery {
        return Recovery(
            diagnosticCode: diagnosticCode ?? self.diagnosticCode,
            readOnly: readOnly ?? self.readOnly,
            reason: reason ?? self.reason,
            remediation: remediation ?? self.remediation
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

public enum Reason: String, Codable {
    case majorVersionMismatch = "major_version_mismatch"
    case startupValidationFailed = "startup_validation_failed"
}

public enum StartupMode: String, Codable {
    case degraded = "degraded"
    case ready = "ready"
    case recovery = "recovery"
}

public enum Transport: String, Codable {
    case mock = "mock"
    case wkwebview = "wkwebview"
}

public enum CerebralHelmBridgeHandshakeResponseType: String, Codable {
    case bridgeHandshakeResponse = "bridge.handshake.response"
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - CerebralHelmBridgeOperationRequest
public struct CerebralHelmBridgeOperationRequest: Codable {
    public let messageID: String
    public let operation: Operation
    public let payload: [String: JSONAny]
    public let schemaVersion: String
    public let type: CerebralHelmBridgeOperationRequestType

    public enum CodingKeys: String, CodingKey {
        case messageID = "messageId"
        case operation, payload, schemaVersion, type
    }

    public init(messageID: String, operation: Operation, payload: [String: JSONAny], schemaVersion: String, type: CerebralHelmBridgeOperationRequestType) {
        self.messageID = messageID
        self.operation = operation
        self.payload = payload
        self.schemaVersion = schemaVersion
        self.type = type
    }
}

// MARK: CerebralHelmBridgeOperationRequest convenience initializers and mutators

public extension CerebralHelmBridgeOperationRequest {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CerebralHelmBridgeOperationRequest.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        messageID: String? = nil,
        operation: Operation? = nil,
        payload: [String: JSONAny]? = nil,
        schemaVersion: String? = nil,
        type: CerebralHelmBridgeOperationRequestType? = nil
    ) -> CerebralHelmBridgeOperationRequest {
        return CerebralHelmBridgeOperationRequest(
            messageID: messageID ?? self.messageID,
            operation: operation ?? self.operation,
            payload: payload ?? self.payload,
            schemaVersion: schemaVersion ?? self.schemaVersion,
            type: type ?? self.type
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

public enum Operation: String, Codable {
    case addChromeProfileReference = "addChromeProfileReference"
    case addLayoutTarget = "addLayoutTarget"
    case addURLReference = "addUrlReference"
    case applyMode = "applyMode"
    case captureLayout = "captureLayout"
    case captureNote = "captureNote"
    case chooseFolder = "chooseFolder"
    case cloneRepository = "cloneRepository"
    case closeAllWindows = "closeAllWindows"
    case closeLayout = "closeLayout"
    case closeWindow = "closeWindow"
    case connectGmail = "connectGmail"
    case connectSpotify = "connectSpotify"
    case createCalendarEvent = "createCalendarEvent"
    case createCourseNote = "createCourseNote"
    case createLinearIssue = "createLinearIssue"
    case createSpotifyPlaylist = "createSpotifyPlaylist"
    case decideConfirmation = "decideConfirmation"
    case deleteSecret = "deleteSecret"
    case getBootstrapState = "getBootstrapState"
    case getCanvasStatus = "getCanvasStatus"
    case getLinearProjectCycle = "getLinearProjectCycle"
    case getRecentActivity = "getRecentActivity"
    case getSecretStatus = "getSecretStatus"
    case getSettings = "getSettings"
    case listApps = "listApps"
    case listCalendars = "listCalendars"
    case listChromeProfiles = "listChromeProfiles"
    case listCourses = "listCourses"
    case listLinearOptions = "listLinearOptions"
    case listMessageRecipients = "listMessageRecipients"
    case listNotes = "listNotes"
    case listSportsEvents = "listSportsEvents"
    case listUnreadMail = "listUnreadMail"
    case listUrls = "listUrls"
    case listWindows = "listWindows"
    case minimizeWindow = "minimizeWindow"
    case openLayout = "openLayout"
    case pinLayoutWindow = "pinLayoutWindow"
    case rebuildKnowledgeIndex = "rebuildKnowledgeIndex"
    case resetCanvas = "resetCanvas"
    case runSpeedTest = "runSpeedTest"
    case runSystemChecks = "runSystemChecks"
    case scaffoldProject = "scaffoldProject"
    case searchNotes = "searchNotes"
    case sendMessage = "sendMessage"
    case setCanvasItemHidden = "setCanvasItemHidden"
    case storeSecret = "storeSecret"
    case submitCommand = "submitCommand"
    case subscribe = "subscribe"
    case suggestCommands = "suggestCommands"
    case surfaceWindow = "surfaceWindow"
    case toggleLayout = "toggleLayout"
    case toggleModeCollapse = "toggleModeCollapse"
    case updateLayout = "updateLayout"
    case updateQuickApps = "updateQuickApps"
    case updateSettings = "updateSettings"
}

public enum CerebralHelmBridgeOperationRequestType: String, Codable {
    case bridgeOperationRequest = "bridge.operation.request"
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - CerebralHelmBridgeOperationResponse
public struct CerebralHelmBridgeOperationResponse: Codable {
    public let error: CerebralHelmBridgeOperationResponseError?
    public let messageID: String
    public let operation: Operation
    public let payload: [String: JSONAny]
    public let schemaVersion: String
    public let status: CerebralHelmBridgeOperationResponseStatus
    public let type: CerebralHelmBridgeOperationResponseType

    public enum CodingKeys: String, CodingKey {
        case error
        case messageID = "messageId"
        case operation, payload, schemaVersion, status, type
    }

    public init(error: CerebralHelmBridgeOperationResponseError?, messageID: String, operation: Operation, payload: [String: JSONAny], schemaVersion: String, status: CerebralHelmBridgeOperationResponseStatus, type: CerebralHelmBridgeOperationResponseType) {
        self.error = error
        self.messageID = messageID
        self.operation = operation
        self.payload = payload
        self.schemaVersion = schemaVersion
        self.status = status
        self.type = type
    }
}

// MARK: CerebralHelmBridgeOperationResponse convenience initializers and mutators

public extension CerebralHelmBridgeOperationResponse {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CerebralHelmBridgeOperationResponse.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        error: CerebralHelmBridgeOperationResponseError?? = nil,
        messageID: String? = nil,
        operation: Operation? = nil,
        payload: [String: JSONAny]? = nil,
        schemaVersion: String? = nil,
        status: CerebralHelmBridgeOperationResponseStatus? = nil,
        type: CerebralHelmBridgeOperationResponseType? = nil
    ) -> CerebralHelmBridgeOperationResponse {
        return CerebralHelmBridgeOperationResponse(
            error: error ?? self.error,
            messageID: messageID ?? self.messageID,
            operation: operation ?? self.operation,
            payload: payload ?? self.payload,
            schemaVersion: schemaVersion ?? self.schemaVersion,
            status: status ?? self.status,
            type: type ?? self.type
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - CerebralHelmBridgeOperationResponseError
public struct CerebralHelmBridgeOperationResponseError: Codable {
    public let category: Category
    public let code: String
    public let details: [String: JSONAny]?
    public let message: String
    public let remediation: String?

    public init(category: Category, code: String, details: [String: JSONAny]?, message: String, remediation: String?) {
        self.category = category
        self.code = code
        self.details = details
        self.message = message
        self.remediation = remediation
    }
}

// MARK: CerebralHelmBridgeOperationResponseError convenience initializers and mutators

public extension CerebralHelmBridgeOperationResponseError {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CerebralHelmBridgeOperationResponseError.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        category: Category? = nil,
        code: String? = nil,
        details: [String: JSONAny]?? = nil,
        message: String? = nil,
        remediation: String?? = nil
    ) -> CerebralHelmBridgeOperationResponseError {
        return CerebralHelmBridgeOperationResponseError(
            category: category ?? self.category,
            code: code ?? self.code,
            details: details ?? self.details,
            message: message ?? self.message,
            remediation: remediation ?? self.remediation
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

public enum Category: String, Codable {
    case adapterContractFailure = "adapter_contract_failure"
    case cancelled = "cancelled"
    case compatibilityMismatch = "compatibility_mismatch"
    case internalFailure = "internal_failure"
    case invalidInput = "invalid_input"
    case invalidTransition = "invalid_transition"
    case permissionDenied = "permission_denied"
    case policyDenied = "policy_denied"
    case providerFailure = "provider_failure"
    case timeout = "timeout"
    case unavailableCapability = "unavailable_capability"
}

public enum CerebralHelmBridgeOperationResponseStatus: String, Codable {
    case error = "error"
    case ok = "ok"
}

public enum CerebralHelmBridgeOperationResponseType: String, Codable {
    case bridgeOperationResponse = "bridge.operation.response"
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

/// The effective durable settings, read on demand over the bridge (`getSettings`) so the
/// settings UI initializes its controls from persisted state instead of hardcoded defaults
/// (NIC-141). Every field is fully resolved: a stored value when set, otherwise the
/// deterministic default. This is the read side of the write-only settings-patch contract;
/// it deliberately omits data that already has a delivery channel — quick apps (bootstrap
/// `modes[].quickApps` + `mode.quickapps.changed`), the login item
/// (`window.__cerebralLoginItem`), and the live command-palette hotkey
/// (`window.__cerebralHotkey`) — so no datum has two sources of truth. Appearance density is
/// not a live setting for now and is intentionally absent.
// MARK: - CerebralHelmSettingsSnapshot
public struct CerebralHelmSettingsSnapshot: Codable {
    public let appearance: SettingsSnapshotAppearance
    /// The user's calendar→mode mapping for the Today panel's per-mode relevance filtering
    /// (NIC-126), keyed by calendar identifier with a mode-id value. Sparse: a calendar is
    /// present only when the user has mapped it — an unmapped calendar's events fall to the
    /// default mode (Executive) at the resolver. Like `modeColors`, this is not fully resolved
    /// but a meaningful-unset map (empty when the user has mapped nothing).
    public let calendarModeMap: [String: String]
    /// When true, policy raises every non-read-only action to require confirmation (the 'Ask
    /// before all actions' tightening; stricter-only, never weakens descriptor policy). Defaults
    /// to false. Enforced when the command runtime is composed.
    public let confirmAllActions: Bool
    /// The mode the app opens in on a fresh launch (the durable setting, resolved as stored
    /// value, else the configured default, else `executive`). This is the default-mode setting,
    /// NOT the currently active mode.
    public let defaultModeID: String
    public let knowledge: SettingsSnapshotKnowledge
    /// Per-mode accent-color overrides, keyed by design-token name (e.g. `executive.primary`)
    /// with a `#rrggbb` hex value. Sparse: a key is present only when the user has customized
    /// that channel — otherwise the shipped mode palette default applies (resolved on the
    /// client, whose token CSS holds the default hex values). Unlike the other snapshot fields
    /// this is not fully resolved, mirroring the meaningful-unset shape of
    /// `knowledge.rootReference`.
    public let modeColors: [String: String]
    public let schemaVersion: String
    public let stocks: SettingsSnapshotStocks
    public let workspace: SettingsSnapshotWorkspace

    public enum CodingKeys: String, CodingKey {
        case appearance, calendarModeMap, confirmAllActions
        case defaultModeID = "defaultModeId"
        case knowledge, modeColors, schemaVersion, stocks, workspace
    }

    public init(appearance: SettingsSnapshotAppearance, calendarModeMap: [String: String], confirmAllActions: Bool, defaultModeID: String, knowledge: SettingsSnapshotKnowledge, modeColors: [String: String], schemaVersion: String, stocks: SettingsSnapshotStocks, workspace: SettingsSnapshotWorkspace) {
        self.appearance = appearance
        self.calendarModeMap = calendarModeMap
        self.confirmAllActions = confirmAllActions
        self.defaultModeID = defaultModeID
        self.knowledge = knowledge
        self.modeColors = modeColors
        self.schemaVersion = schemaVersion
        self.stocks = stocks
        self.workspace = workspace
    }
}

// MARK: CerebralHelmSettingsSnapshot convenience initializers and mutators

public extension CerebralHelmSettingsSnapshot {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CerebralHelmSettingsSnapshot.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        appearance: SettingsSnapshotAppearance? = nil,
        calendarModeMap: [String: String]? = nil,
        confirmAllActions: Bool? = nil,
        defaultModeID: String? = nil,
        knowledge: SettingsSnapshotKnowledge? = nil,
        modeColors: [String: String]? = nil,
        schemaVersion: String? = nil,
        stocks: SettingsSnapshotStocks? = nil,
        workspace: SettingsSnapshotWorkspace? = nil
    ) -> CerebralHelmSettingsSnapshot {
        return CerebralHelmSettingsSnapshot(
            appearance: appearance ?? self.appearance,
            calendarModeMap: calendarModeMap ?? self.calendarModeMap,
            confirmAllActions: confirmAllActions ?? self.confirmAllActions,
            defaultModeID: defaultModeID ?? self.defaultModeID,
            knowledge: knowledge ?? self.knowledge,
            modeColors: modeColors ?? self.modeColors,
            schemaVersion: schemaVersion ?? self.schemaVersion,
            stocks: stocks ?? self.stocks,
            workspace: workspace ?? self.workspace
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - SettingsSnapshotAppearance
public struct SettingsSnapshotAppearance: Codable {
    /// The display name of the assistant across the dashboard (bottom bar, center stage).
    /// Resolves to the stored value, else the default `Heimlich`.
    public let assistantName: String
    /// Whether motion is reduced across the dashboard. Defaults to false when unset.
    public let reducedMotion: Bool

    public init(assistantName: String, reducedMotion: Bool) {
        self.assistantName = assistantName
        self.reducedMotion = reducedMotion
    }
}

// MARK: SettingsSnapshotAppearance convenience initializers and mutators

public extension SettingsSnapshotAppearance {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(SettingsSnapshotAppearance.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        assistantName: String? = nil,
        reducedMotion: Bool? = nil
    ) -> SettingsSnapshotAppearance {
        return SettingsSnapshotAppearance(
            assistantName: assistantName ?? self.assistantName,
            reducedMotion: reducedMotion ?? self.reducedMotion
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - SettingsSnapshotKnowledge
public struct SettingsSnapshotKnowledge: Codable {
    /// The configured knowledge-root reference id, or null when no root has been chosen (a
    /// meaningful unset state, unlike the other fields).
    public let rootReference: String?

    public init(rootReference: String?) {
        self.rootReference = rootReference
    }
}

// MARK: SettingsSnapshotKnowledge convenience initializers and mutators

public extension SettingsSnapshotKnowledge {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(SettingsSnapshotKnowledge.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        rootReference: String?? = nil
    ) -> SettingsSnapshotKnowledge {
        return SettingsSnapshotKnowledge(
            rootReference: rootReference ?? self.rootReference
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - SettingsSnapshotStocks
public struct SettingsSnapshotStocks: Codable {
    /// The user's tracked stock symbols for the Executive Stocks widget (NIC-128), in display
    /// order. Fully resolved: the stored list when set, otherwise the shipped starter list. An
    /// empty array is a meaningful state — the user cleared their tickers — and renders the
    /// widget's empty prompt.
    public let tickers: [String]

    public init(tickers: [String]) {
        self.tickers = tickers
    }
}

// MARK: SettingsSnapshotStocks convenience initializers and mutators

public extension SettingsSnapshotStocks {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(SettingsSnapshotStocks.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        tickers: [String]? = nil
    ) -> SettingsSnapshotStocks {
        return SettingsSnapshotStocks(
            tickers: tickers ?? self.tickers
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - SettingsSnapshotWorkspace
public struct SettingsSnapshotWorkspace: Codable {
    /// The stable display id layout mode opens on and whose bottom bar shows the hotswap pill
    /// (NIC-142). Resolves to the `system-primary` sentinel when unset; a stale or disconnected
    /// id degrades to the main display, then system primary, at the shell.
    public let layoutDisplayID: String
    /// The stable display id the main dashboard backdrop is hosted on. Resolves to the
    /// `system-primary` sentinel when unset; a stale or disconnected id also degrades to system
    /// primary at the shell.
    public let mainDisplayID: String
    /// Whether a mode switch hides the outgoing mode's apps and returns the incoming mode's
    /// stored ones (NIC-85). Defaults to false when unset.
    public let windowsStoredByMode: Bool

    public enum CodingKeys: String, CodingKey {
        case layoutDisplayID = "layoutDisplayId"
        case mainDisplayID = "mainDisplayId"
        case windowsStoredByMode
    }

    public init(layoutDisplayID: String, mainDisplayID: String, windowsStoredByMode: Bool) {
        self.layoutDisplayID = layoutDisplayID
        self.mainDisplayID = mainDisplayID
        self.windowsStoredByMode = windowsStoredByMode
    }
}

// MARK: SettingsSnapshotWorkspace convenience initializers and mutators

public extension SettingsSnapshotWorkspace {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(SettingsSnapshotWorkspace.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        layoutDisplayID: String? = nil,
        mainDisplayID: String? = nil,
        windowsStoredByMode: Bool? = nil
    ) -> SettingsSnapshotWorkspace {
        return SettingsSnapshotWorkspace(
            layoutDisplayID: layoutDisplayID ?? self.layoutDisplayID,
            mainDisplayID: mainDisplayID ?? self.mainDisplayID,
            windowsStoredByMode: windowsStoredByMode ?? self.windowsStoredByMode
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - CerebralHelmCommandEnvelope
public struct CerebralHelmCommandEnvelope: Codable {
    public let correlationID: String?
    public let id: String
    public let payload: [String: JSONAny]
    public let privacy: Privacy
    public let rawInput: String
    public let schemaVersion: String
    public let source: CerebralHelmCommandEnvelopeSource
    public let timestamp: Date
    public let type: CerebralHelmCommandEnvelopeType

    public enum CodingKeys: String, CodingKey {
        case correlationID = "correlationId"
        case id, payload, privacy, rawInput, schemaVersion, source, timestamp, type
    }

    public init(correlationID: String?, id: String, payload: [String: JSONAny], privacy: Privacy, rawInput: String, schemaVersion: String, source: CerebralHelmCommandEnvelopeSource, timestamp: Date, type: CerebralHelmCommandEnvelopeType) {
        self.correlationID = correlationID
        self.id = id
        self.payload = payload
        self.privacy = privacy
        self.rawInput = rawInput
        self.schemaVersion = schemaVersion
        self.source = source
        self.timestamp = timestamp
        self.type = type
    }
}

// MARK: CerebralHelmCommandEnvelope convenience initializers and mutators

public extension CerebralHelmCommandEnvelope {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CerebralHelmCommandEnvelope.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        correlationID: String?? = nil,
        id: String? = nil,
        payload: [String: JSONAny]? = nil,
        privacy: Privacy? = nil,
        rawInput: String? = nil,
        schemaVersion: String? = nil,
        source: CerebralHelmCommandEnvelopeSource? = nil,
        timestamp: Date? = nil,
        type: CerebralHelmCommandEnvelopeType? = nil
    ) -> CerebralHelmCommandEnvelope {
        return CerebralHelmCommandEnvelope(
            correlationID: correlationID ?? self.correlationID,
            id: id ?? self.id,
            payload: payload ?? self.payload,
            privacy: privacy ?? self.privacy,
            rawInput: rawInput ?? self.rawInput,
            schemaVersion: schemaVersion ?? self.schemaVersion,
            source: source ?? self.source,
            timestamp: timestamp ?? self.timestamp,
            type: type ?? self.type
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - Privacy
public struct Privacy: Codable {
    public let cloudPolicy: CloudPolicy
    public let sensitivity: Sensitivity

    public init(cloudPolicy: CloudPolicy, sensitivity: Sensitivity) {
        self.cloudPolicy = cloudPolicy
        self.sensitivity = sensitivity
    }
}

// MARK: Privacy convenience initializers and mutators

public extension Privacy {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(Privacy.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        cloudPolicy: CloudPolicy? = nil,
        sensitivity: Sensitivity? = nil
    ) -> Privacy {
        return Privacy(
            cloudPolicy: cloudPolicy ?? self.cloudPolicy,
            sensitivity: sensitivity ?? self.sensitivity
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

/// Whether the note may be sent to a cloud provider. Defaults to deny; never defaults to
/// allow.
public enum CloudPolicy: String, Codable {
    case allow = "allow"
    case ask = "ask"
    case deny = "deny"
}

/// Defaults to private when unspecified.
///
/// Privacy label recorded in the note's frontmatter. It is metadata, not access control -
/// nothing today restricts reading a note based on it. Omitted degrades to `private`, which
/// is the right answer unless the user's own words call for another; do not judge the
/// content's sensitivity yourself.
public enum Sensitivity: String, Codable {
    case secret = "secret"
    case sensitive = "sensitive"
    case sensitivityPrivate = "private"
    case sensitivityPublic = "public"
}

public enum CerebralHelmCommandEnvelopeSource: String, Codable {
    case agent = "agent"
    case automation = "automation"
    case cli = "cli"
    case dashboard = "dashboard"
    case hotkey = "hotkey"
    case ios = "ios"
    case system = "system"
    case voice = "voice"
}

public enum CerebralHelmCommandEnvelopeType: String, Codable {
    case commandSubmit = "command.submit"
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - CerebralHelmCommandLifecycleEvent
public struct CerebralHelmCommandLifecycleEvent: Codable {
    public let commandID: String
    public let currentStatus: PreviousStatus
    public let error: CerebralHelmCommandLifecycleEventError?
    public let id: String
    public let message: String?
    public let previousStatus: PreviousStatus?
    public let schemaVersion: String
    public let timestamp: Date
    public let type: CerebralHelmCommandLifecycleEventType

    public enum CodingKeys: String, CodingKey {
        case commandID = "commandId"
        case currentStatus, error, id, message, previousStatus, schemaVersion, timestamp, type
    }

    public init(commandID: String, currentStatus: PreviousStatus, error: CerebralHelmCommandLifecycleEventError?, id: String, message: String?, previousStatus: PreviousStatus?, schemaVersion: String, timestamp: Date, type: CerebralHelmCommandLifecycleEventType) {
        self.commandID = commandID
        self.currentStatus = currentStatus
        self.error = error
        self.id = id
        self.message = message
        self.previousStatus = previousStatus
        self.schemaVersion = schemaVersion
        self.timestamp = timestamp
        self.type = type
    }
}

// MARK: CerebralHelmCommandLifecycleEvent convenience initializers and mutators

public extension CerebralHelmCommandLifecycleEvent {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CerebralHelmCommandLifecycleEvent.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        commandID: String? = nil,
        currentStatus: PreviousStatus? = nil,
        error: CerebralHelmCommandLifecycleEventError?? = nil,
        id: String? = nil,
        message: String?? = nil,
        previousStatus: PreviousStatus?? = nil,
        schemaVersion: String? = nil,
        timestamp: Date? = nil,
        type: CerebralHelmCommandLifecycleEventType? = nil
    ) -> CerebralHelmCommandLifecycleEvent {
        return CerebralHelmCommandLifecycleEvent(
            commandID: commandID ?? self.commandID,
            currentStatus: currentStatus ?? self.currentStatus,
            error: error ?? self.error,
            id: id ?? self.id,
            message: message ?? self.message,
            previousStatus: previousStatus ?? self.previousStatus,
            schemaVersion: schemaVersion ?? self.schemaVersion,
            timestamp: timestamp ?? self.timestamp,
            type: type ?? self.type
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

public enum PreviousStatus: String, Codable {
    case cancelled = "cancelled"
    case failed = "failed"
    case planned = "planned"
    case received = "received"
    case requiresConfirmation = "requires_confirmation"
    case running = "running"
    case succeeded = "succeeded"
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - CerebralHelmCommandLifecycleEventError
public struct CerebralHelmCommandLifecycleEventError: Codable {
    public let category: Category
    public let code: String
    public let details: [String: JSONAny]?
    public let message: String
    public let remediation: String?

    public init(category: Category, code: String, details: [String: JSONAny]?, message: String, remediation: String?) {
        self.category = category
        self.code = code
        self.details = details
        self.message = message
        self.remediation = remediation
    }
}

// MARK: CerebralHelmCommandLifecycleEventError convenience initializers and mutators

public extension CerebralHelmCommandLifecycleEventError {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CerebralHelmCommandLifecycleEventError.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        category: Category? = nil,
        code: String? = nil,
        details: [String: JSONAny]?? = nil,
        message: String? = nil,
        remediation: String?? = nil
    ) -> CerebralHelmCommandLifecycleEventError {
        return CerebralHelmCommandLifecycleEventError(
            category: category ?? self.category,
            code: code ?? self.code,
            details: details ?? self.details,
            message: message ?? self.message,
            remediation: remediation ?? self.remediation
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

public enum CerebralHelmCommandLifecycleEventType: String, Codable {
    case commandLifecycleTransition = "command.lifecycle.transition"
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - CerebralHelmCommandTerminalResult
public struct CerebralHelmCommandTerminalResult: Codable {
    public let commandID: String
    public let completedAt: Date
    public let error: CerebralHelmCommandTerminalResultError?
    public let output: [String: JSONAny]
    public let schemaVersion: String
    public let status: CerebralHelmCommandTerminalResultStatus
    public let summary: String

    public enum CodingKeys: String, CodingKey {
        case commandID = "commandId"
        case completedAt, error, output, schemaVersion, status, summary
    }

    public init(commandID: String, completedAt: Date, error: CerebralHelmCommandTerminalResultError?, output: [String: JSONAny], schemaVersion: String, status: CerebralHelmCommandTerminalResultStatus, summary: String) {
        self.commandID = commandID
        self.completedAt = completedAt
        self.error = error
        self.output = output
        self.schemaVersion = schemaVersion
        self.status = status
        self.summary = summary
    }
}

// MARK: CerebralHelmCommandTerminalResult convenience initializers and mutators

public extension CerebralHelmCommandTerminalResult {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CerebralHelmCommandTerminalResult.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        commandID: String? = nil,
        completedAt: Date? = nil,
        error: CerebralHelmCommandTerminalResultError?? = nil,
        output: [String: JSONAny]? = nil,
        schemaVersion: String? = nil,
        status: CerebralHelmCommandTerminalResultStatus? = nil,
        summary: String? = nil
    ) -> CerebralHelmCommandTerminalResult {
        return CerebralHelmCommandTerminalResult(
            commandID: commandID ?? self.commandID,
            completedAt: completedAt ?? self.completedAt,
            error: error ?? self.error,
            output: output ?? self.output,
            schemaVersion: schemaVersion ?? self.schemaVersion,
            status: status ?? self.status,
            summary: summary ?? self.summary
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - CerebralHelmCommandTerminalResultError
public struct CerebralHelmCommandTerminalResultError: Codable {
    public let category: Category
    public let code: String
    public let details: [String: JSONAny]?
    public let message: String
    public let remediation: String?

    public init(category: Category, code: String, details: [String: JSONAny]?, message: String, remediation: String?) {
        self.category = category
        self.code = code
        self.details = details
        self.message = message
        self.remediation = remediation
    }
}

// MARK: CerebralHelmCommandTerminalResultError convenience initializers and mutators

public extension CerebralHelmCommandTerminalResultError {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CerebralHelmCommandTerminalResultError.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        category: Category? = nil,
        code: String? = nil,
        details: [String: JSONAny]?? = nil,
        message: String? = nil,
        remediation: String?? = nil
    ) -> CerebralHelmCommandTerminalResultError {
        return CerebralHelmCommandTerminalResultError(
            category: category ?? self.category,
            code: code ?? self.code,
            details: details ?? self.details,
            message: message ?? self.message,
            remediation: remediation ?? self.remediation
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

public enum CerebralHelmCommandTerminalResultStatus: String, Codable {
    case cancelled = "cancelled"
    case failed = "failed"
    case succeeded = "succeeded"
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - CerebralHelmStructuredError
public struct CerebralHelmStructuredError: Codable {
    public let category: Category
    public let code: String
    public let details: [String: JSONAny]?
    public let message: String
    public let remediation: String?

    public init(category: Category, code: String, details: [String: JSONAny]?, message: String, remediation: String?) {
        self.category = category
        self.code = code
        self.details = details
        self.message = message
        self.remediation = remediation
    }
}

// MARK: CerebralHelmStructuredError convenience initializers and mutators

public extension CerebralHelmStructuredError {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CerebralHelmStructuredError.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        category: Category? = nil,
        code: String? = nil,
        details: [String: JSONAny]?? = nil,
        message: String? = nil,
        remediation: String?? = nil
    ) -> CerebralHelmStructuredError {
        return CerebralHelmStructuredError(
            category: category ?? self.category,
            code: code ?? self.code,
            details: details ?? self.details,
            message: message ?? self.message,
            remediation: remediation ?? self.remediation
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - CerebralHelmAgentSurfaceConfig
public struct CerebralHelmAgentSurfaceConfig: Codable {
    public let allowedKnowledgeRoots: [String]?
    public let allowedToolIDS: [String]?
    public let extensions: [String: JSONAny]?
    public let id: String
    public let label: String
    public let status: DashboardAgentAvailability
    public let summary: String

    public enum CodingKeys: String, CodingKey {
        case allowedKnowledgeRoots
        case allowedToolIDS = "allowedToolIds"
        case extensions, id, label, status, summary
    }

    public init(allowedKnowledgeRoots: [String]?, allowedToolIDS: [String]?, extensions: [String: JSONAny]?, id: String, label: String, status: DashboardAgentAvailability, summary: String) {
        self.allowedKnowledgeRoots = allowedKnowledgeRoots
        self.allowedToolIDS = allowedToolIDS
        self.extensions = extensions
        self.id = id
        self.label = label
        self.status = status
        self.summary = summary
    }
}

// MARK: CerebralHelmAgentSurfaceConfig convenience initializers and mutators

public extension CerebralHelmAgentSurfaceConfig {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CerebralHelmAgentSurfaceConfig.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        allowedKnowledgeRoots: [String]?? = nil,
        allowedToolIDS: [String]?? = nil,
        extensions: [String: JSONAny]?? = nil,
        id: String? = nil,
        label: String? = nil,
        status: DashboardAgentAvailability? = nil,
        summary: String? = nil
    ) -> CerebralHelmAgentSurfaceConfig {
        return CerebralHelmAgentSurfaceConfig(
            allowedKnowledgeRoots: allowedKnowledgeRoots ?? self.allowedKnowledgeRoots,
            allowedToolIDS: allowedToolIDS ?? self.allowedToolIDS,
            extensions: extensions ?? self.extensions,
            id: id ?? self.id,
            label: label ?? self.label,
            status: status ?? self.status,
            summary: summary ?? self.summary
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - CerebralHelmApplicationDefaults
public struct CerebralHelmApplicationDefaults: Codable {
    public let defaultModeID: String
    public let enabledAgentIDS: [String]
    public let enabledToolIDS: [String]
    public let extensions: [String: JSONAny]?
    public let schemaVersion: String

    public enum CodingKeys: String, CodingKey {
        case defaultModeID = "defaultModeId"
        case enabledAgentIDS = "enabledAgentIds"
        case enabledToolIDS = "enabledToolIds"
        case extensions, schemaVersion
    }

    public init(defaultModeID: String, enabledAgentIDS: [String], enabledToolIDS: [String], extensions: [String: JSONAny]?, schemaVersion: String) {
        self.defaultModeID = defaultModeID
        self.enabledAgentIDS = enabledAgentIDS
        self.enabledToolIDS = enabledToolIDS
        self.extensions = extensions
        self.schemaVersion = schemaVersion
    }
}

// MARK: CerebralHelmApplicationDefaults convenience initializers and mutators

public extension CerebralHelmApplicationDefaults {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CerebralHelmApplicationDefaults.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        defaultModeID: String? = nil,
        enabledAgentIDS: [String]? = nil,
        enabledToolIDS: [String]? = nil,
        extensions: [String: JSONAny]?? = nil,
        schemaVersion: String? = nil
    ) -> CerebralHelmApplicationDefaults {
        return CerebralHelmApplicationDefaults(
            defaultModeID: defaultModeID ?? self.defaultModeID,
            enabledAgentIDS: enabledAgentIDS ?? self.enabledAgentIDS,
            enabledToolIDS: enabledToolIDS ?? self.enabledToolIDS,
            extensions: extensions ?? self.extensions,
            schemaVersion: schemaVersion ?? self.schemaVersion
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - CerebralHelmConfigValidationError
public struct CerebralHelmConfigValidationError: Codable {
    public let expected, field, file, message: String
    public let remediation: String
    public let schemaVersion: String

    public init(expected: String, field: String, file: String, message: String, remediation: String, schemaVersion: String) {
        self.expected = expected
        self.field = field
        self.file = file
        self.message = message
        self.remediation = remediation
        self.schemaVersion = schemaVersion
    }
}

// MARK: CerebralHelmConfigValidationError convenience initializers and mutators

public extension CerebralHelmConfigValidationError {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CerebralHelmConfigValidationError.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        expected: String? = nil,
        field: String? = nil,
        file: String? = nil,
        message: String? = nil,
        remediation: String? = nil,
        schemaVersion: String? = nil
    ) -> CerebralHelmConfigValidationError {
        return CerebralHelmConfigValidationError(
            expected: expected ?? self.expected,
            field: field ?? self.field,
            file: file ?? self.file,
            message: message ?? self.message,
            remediation: remediation ?? self.remediation,
            schemaVersion: schemaVersion ?? self.schemaVersion
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

/// A user's per-mode override, merged onto the shipped mode config by id — the
/// user-overrides layer of the config loader. It is edited inline from the mode surface
/// (e.g. a pencil on a quick-app icon), and is deliberately separate from the settings
/// patch, which carries cross-cutting preferences such as per-mode color and the knowledge
/// root. Only fields a user may safely tailor per mode appear here; it can never weaken risk
/// or confirmation policy. quickApps is the first overridable field; further inline-editable
/// fields (e.g. widgets) extend this set later. Override files live under the environment
/// state root, never in the shipped config.
// MARK: - CerebralHelmModeOverride
public struct CerebralHelmModeOverride: Codable {
    public let extensions: [String: JSONAny]?
    public let id: String
    /// The mode's authored window layout (NIC-142), replacing the shipped layout. Its structure
    /// matches the mode config's `layout` (mode.schema.json `$defs/layout`); it is carried
    /// opaquely here — validated structurally in the config validator by decoding it into the
    /// same Layout type — so the generated override type stays a flat document and the layout's
    /// named types are defined once, on the mode config.
    public let layout: [String: JSONAny]?
    public let quickApps: [String]?
    public let schemaVersion: String

    public init(extensions: [String: JSONAny]?, id: String, layout: [String: JSONAny]?, quickApps: [String]?, schemaVersion: String) {
        self.extensions = extensions
        self.id = id
        self.layout = layout
        self.quickApps = quickApps
        self.schemaVersion = schemaVersion
    }
}

// MARK: CerebralHelmModeOverride convenience initializers and mutators

public extension CerebralHelmModeOverride {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CerebralHelmModeOverride.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        extensions: [String: JSONAny]?? = nil,
        id: String? = nil,
        layout: [String: JSONAny]?? = nil,
        quickApps: [String]?? = nil,
        schemaVersion: String? = nil
    ) -> CerebralHelmModeOverride {
        return CerebralHelmModeOverride(
            extensions: extensions ?? self.extensions,
            id: id ?? self.id,
            layout: layout ?? self.layout,
            quickApps: quickApps ?? self.quickApps,
            schemaVersion: schemaVersion ?? self.schemaVersion
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - CerebralHelmModeConfig
public struct CerebralHelmModeConfig: Codable {
    public let calendarProfile: CalendarProfile?
    public let extensions: [String: JSONAny]?
    public let greeting: Greeting?
    public let id: String
    public let label: String
    /// The mode's authored window layout (NIC-142). `windows` are static app/URL placements; the
    /// optional `quickToggle` is the single dynamic slot whose one visible window swaps between
    /// N targets from the bottom bar. Frames reuse the window.arrange named vocabulary — never
    /// arbitrary coordinates. The whole layout opens on the chosen `display`.
    public let layout: Layout?
    public let layoutID: String?
    public let newsProfile: NewsProfile?
    public let projectHints: [String]?
    /// Exactly 8 ordered quick-action slots forming the binding 4+4 ambient grid (slots 0-3
    /// render as compact bars, 4-7 as boxes; the shared shell owns that geometry). Each slot is
    /// an action id or null for an unconfigured slot (rendered as an 'add action' button).
    /// Non-null ids must be unique; null slots may repeat.
    public let quickActions: [String?]
    public let quickApps: [String]
    public let theme: Theme
    public let widgets: Widgets

    public enum CodingKeys: String, CodingKey {
        case calendarProfile, extensions, greeting, id, label, layout
        case layoutID = "layoutId"
        case newsProfile, projectHints, quickActions, quickApps, theme, widgets
    }

    public init(calendarProfile: CalendarProfile?, extensions: [String: JSONAny]?, greeting: Greeting?, id: String, label: String, layout: Layout?, layoutID: String?, newsProfile: NewsProfile?, projectHints: [String]?, quickActions: [String?], quickApps: [String], theme: Theme, widgets: Widgets) {
        self.calendarProfile = calendarProfile
        self.extensions = extensions
        self.greeting = greeting
        self.id = id
        self.label = label
        self.layout = layout
        self.layoutID = layoutID
        self.newsProfile = newsProfile
        self.projectHints = projectHints
        self.quickActions = quickActions
        self.quickApps = quickApps
        self.theme = theme
        self.widgets = widgets
    }
}

// MARK: CerebralHelmModeConfig convenience initializers and mutators

public extension CerebralHelmModeConfig {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CerebralHelmModeConfig.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        calendarProfile: CalendarProfile?? = nil,
        extensions: [String: JSONAny]?? = nil,
        greeting: Greeting?? = nil,
        id: String? = nil,
        label: String? = nil,
        layout: Layout?? = nil,
        layoutID: String?? = nil,
        newsProfile: NewsProfile?? = nil,
        projectHints: [String]?? = nil,
        quickActions: [String?]? = nil,
        quickApps: [String]? = nil,
        theme: Theme? = nil,
        widgets: Widgets? = nil
    ) -> CerebralHelmModeConfig {
        return CerebralHelmModeConfig(
            calendarProfile: calendarProfile ?? self.calendarProfile,
            extensions: extensions ?? self.extensions,
            greeting: greeting ?? self.greeting,
            id: id ?? self.id,
            label: label ?? self.label,
            layout: layout ?? self.layout,
            layoutID: layoutID ?? self.layoutID,
            newsProfile: newsProfile ?? self.newsProfile,
            projectHints: projectHints ?? self.projectHints,
            quickActions: quickActions ?? self.quickActions,
            quickApps: quickApps ?? self.quickApps,
            theme: theme ?? self.theme,
            widgets: widgets ?? self.widgets
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

public enum CalendarProfile: String, Codable {
    case academic = "academic"
    case all = "all"
    case engineering = "engineering"
    case leisure = "leisure"
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - Greeting
public struct Greeting: Codable {
    public let directive: String?
    public let fallback, persona: String

    public init(directive: String?, fallback: String, persona: String) {
        self.directive = directive
        self.fallback = fallback
        self.persona = persona
    }
}

// MARK: Greeting convenience initializers and mutators

public extension Greeting {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(Greeting.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        directive: String?? = nil,
        fallback: String? = nil,
        persona: String? = nil
    ) -> Greeting {
        return Greeting(
            directive: directive ?? self.directive,
            fallback: fallback ?? self.fallback,
            persona: persona ?? self.persona
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

/// The mode's authored window layout (NIC-142). `windows` are static app/URL placements; the
/// optional `quickToggle` is the single dynamic slot whose one visible window swaps between
/// N targets from the bottom bar. Frames reuse the window.arrange named vocabulary — never
/// arbitrary coordinates. The whole layout opens on the chosen `display`.
// MARK: - Layout
public struct Layout: Codable {
    public let display: Display
    public let quickToggle: QuickToggle?
    public let windows: [Window]

    public init(display: Display, quickToggle: QuickToggle?, windows: [Window]) {
        self.display = display
        self.quickToggle = quickToggle
        self.windows = windows
    }
}

// MARK: Layout convenience initializers and mutators

public extension Layout {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(Layout.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        display: Display? = nil,
        quickToggle: QuickToggle?? = nil,
        windows: [Window]? = nil
    ) -> Layout {
        return Layout(
            display: display ?? self.display,
            quickToggle: quickToggle ?? self.quickToggle,
            windows: windows ?? self.windows
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

/// Which display the whole arrangement targets (NIC-142 layout mode). Absent or 'primary'
/// targets the primary display; 'secondary' targets the first non-primary display, degrading
/// to primary when none is attached. Frames resolve against the chosen display's visible
/// area.
public enum Display: String, Codable {
    case primary = "primary"
    case secondary = "secondary"
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - QuickToggle
public struct QuickToggle: Codable {
    public let frame: Frame
    public let targets: [Target]

    public init(frame: Frame, targets: [Target]) {
        self.frame = frame
        self.targets = targets
    }
}

// MARK: QuickToggle convenience initializers and mutators

public extension QuickToggle {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(QuickToggle.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        frame: Frame? = nil,
        targets: [Target]? = nil
    ) -> QuickToggle {
        return QuickToggle(
            frame: frame ?? self.frame,
            targets: targets ?? self.targets
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

/// Which region of the target display's visible area the window fills. Halves and thirds are
/// measured against that display rather than the window's current size, and `centered` is a
/// three-quarter-size window inset from every edge, not a move that preserves the window's
/// size. Only these named frames are accepted; arbitrary coordinates are not.
public enum Frame: String, Codable {
    case bottomHalf = "bottom-half"
    case centered = "centered"
    case full = "full"
    case leftHalf = "left-half"
    case leftThird = "left-third"
    case leftTwoThirds = "left-two-thirds"
    case rightHalf = "right-half"
    case rightThird = "right-third"
    case rightTwoThirds = "right-two-thirds"
    case topHalf = "top-half"
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - Target
public struct Target: Codable {
    public let kind: Kind
    public let ref: String

    public init(kind: Kind, ref: String) {
        self.kind = kind
        self.ref = ref
    }
}

// MARK: Target convenience initializers and mutators

public extension Target {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(Target.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        kind: Kind? = nil,
        ref: String? = nil
    ) -> Target {
        return Target(
            kind: kind ?? self.kind,
            ref: ref ?? self.ref
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

public enum Kind: String, Codable {
    case app = "app"
    case url = "url"
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - Window
public struct Window: Codable {
    public let frame: Frame
    public let kind: Kind
    public let ref: String

    public init(frame: Frame, kind: Kind, ref: String) {
        self.frame = frame
        self.kind = kind
        self.ref = ref
    }
}

// MARK: Window convenience initializers and mutators

public extension Window {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(Window.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        frame: Frame? = nil,
        kind: Kind? = nil,
        ref: String? = nil
    ) -> Window {
        return Window(
            frame: frame ?? self.frame,
            kind: kind ?? self.kind,
            ref: ref ?? self.ref
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

public enum NewsProfile: String, Codable {
    case academic = "academic"
    case broad = "broad"
    case engineering = "engineering"
    case interest = "interest"
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - Theme
public struct Theme: Codable {
    public let accentPrimary, accentSecondary: String

    public init(accentPrimary: String, accentSecondary: String) {
        self.accentPrimary = accentPrimary
        self.accentSecondary = accentSecondary
    }
}

// MARK: Theme convenience initializers and mutators

public extension Theme {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(Theme.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        accentPrimary: String? = nil,
        accentSecondary: String? = nil
    ) -> Theme {
        return Theme(
            accentPrimary: accentPrimary ?? self.accentPrimary,
            accentSecondary: accentSecondary ?? self.accentSecondary
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - Widgets
public struct Widgets: Codable {
    public let widgetsLeft, widgetsRight: String

    public enum CodingKeys: String, CodingKey {
        case widgetsLeft = "left"
        case widgetsRight = "right"
    }

    public init(widgetsLeft: String, widgetsRight: String) {
        self.widgetsLeft = widgetsLeft
        self.widgetsRight = widgetsRight
    }
}

// MARK: Widgets convenience initializers and mutators

public extension Widgets {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(Widgets.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        widgetsLeft: String? = nil,
        widgetsRight: String? = nil
    ) -> Widgets {
        return Widgets(
            widgetsLeft: widgetsLeft ?? self.widgetsLeft,
            widgetsRight: widgetsRight ?? self.widgetsRight
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

/// Which model serves each capability profile, how much context it may allocate, and how
/// long it stays resident (ADR-009). Product logic addresses profiles; exact model ids are
/// resolved here so that no named local model becomes an architectural dependency. Optional:
/// with no such file the app runs exactly as it does today, with no model attached.
// MARK: - CerebralHelmModelProfileCatalog
public struct CerebralHelmModelProfileCatalog: Codable {
    public let extensions: [String: JSONAny]?
    public let modelProfiles: [ModelProfile]
    /// Advisory only, never enforced: how much model weight this machine can hold resident
    /// before it swaps. Measured at ~48 GB on the target Mac (default GPU allocation); two
    /// resident 30B models came to ~51 GB and drove 18 GB of swap. Recorded so the figure is not
    /// rediscovered the hard way.
    public let residentBudgetGigabytes: Double?
    public let schemaVersion: String

    public init(extensions: [String: JSONAny]?, modelProfiles: [ModelProfile], residentBudgetGigabytes: Double?, schemaVersion: String) {
        self.extensions = extensions
        self.modelProfiles = modelProfiles
        self.residentBudgetGigabytes = residentBudgetGigabytes
        self.schemaVersion = schemaVersion
    }
}

// MARK: CerebralHelmModelProfileCatalog convenience initializers and mutators

public extension CerebralHelmModelProfileCatalog {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CerebralHelmModelProfileCatalog.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        extensions: [String: JSONAny]?? = nil,
        modelProfiles: [ModelProfile]? = nil,
        residentBudgetGigabytes: Double?? = nil,
        schemaVersion: String? = nil
    ) -> CerebralHelmModelProfileCatalog {
        return CerebralHelmModelProfileCatalog(
            extensions: extensions ?? self.extensions,
            modelProfiles: modelProfiles ?? self.modelProfiles,
            residentBudgetGigabytes: residentBudgetGigabytes ?? self.residentBudgetGigabytes,
            schemaVersion: schemaVersion ?? self.schemaVersion
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - ModelProfile
public struct ModelProfile: Codable {
    /// Context window to allocate. A memory lever, not only a capability one: left unset a
    /// runtime allocates the model's full advertised window (131K/262K), which took a 21 GB
    /// model to 29 GB resident. Capping to 16K recovered ~6 GB.
    public let contextTokens: Int
    public let extensions: [String: JSONAny]?
    /// The capability profile product logic asks for. 'local' is not a capability but a policy:
    /// a surface that must never leave this machine even if a cloud escape hatch is later
    /// enabled.
    public let id: ModelProfileID
    /// The runtime's own tag for the model, e.g. 'qwen3.6:35b-mlx'.
    public let modelID: String
    /// pinned for an always-on surface, where a ~70 s cold reload would be felt every time;
    /// evictAfterUse for a rare specialist that would otherwise hold tens of gigabytes.
    public let residency: Residency
    /// Required when residency is 'bounded', and rejected otherwise.
    public let residencyIdleSeconds: Int?
    /// Advisory estimate of this model's resident footprint, counted once per distinct model id.
    /// An owner-maintained figure that drifts with quantisation; never enforced.
    public let residentGigabytes: Double?
    /// Which inference runtime serves it — 'ollama', 'llama.cpp', 'mlx'. A pattern rather than
    /// an enum so adding a runtime is a config change, not a schema change.
    public let runtimeID: String
    /// Whether the model may deliberate. Off everywhere except deep research: composition from a
    /// typed snapshot is rendering, not reasoning, and leaving it on cost 79-130 s against 9-17
    /// s.
    public let thinking: Bool
    /// Wall-clock budget for one request. Defaults to 120 when absent.
    public let timeoutSeconds: Int?

    public enum CodingKeys: String, CodingKey {
        case contextTokens, extensions, id
        case modelID = "modelId"
        case residency, residencyIdleSeconds, residentGigabytes
        case runtimeID = "runtimeId"
        case thinking, timeoutSeconds
    }

    public init(contextTokens: Int, extensions: [String: JSONAny]?, id: ModelProfileID, modelID: String, residency: Residency, residencyIdleSeconds: Int?, residentGigabytes: Double?, runtimeID: String, thinking: Bool, timeoutSeconds: Int?) {
        self.contextTokens = contextTokens
        self.extensions = extensions
        self.id = id
        self.modelID = modelID
        self.residency = residency
        self.residencyIdleSeconds = residencyIdleSeconds
        self.residentGigabytes = residentGigabytes
        self.runtimeID = runtimeID
        self.thinking = thinking
        self.timeoutSeconds = timeoutSeconds
    }
}

// MARK: ModelProfile convenience initializers and mutators

public extension ModelProfile {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(ModelProfile.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        contextTokens: Int? = nil,
        extensions: [String: JSONAny]?? = nil,
        id: ModelProfileID? = nil,
        modelID: String? = nil,
        residency: Residency? = nil,
        residencyIdleSeconds: Int?? = nil,
        residentGigabytes: Double?? = nil,
        runtimeID: String? = nil,
        thinking: Bool? = nil,
        timeoutSeconds: Int?? = nil
    ) -> ModelProfile {
        return ModelProfile(
            contextTokens: contextTokens ?? self.contextTokens,
            extensions: extensions ?? self.extensions,
            id: id ?? self.id,
            modelID: modelID ?? self.modelID,
            residency: residency ?? self.residency,
            residencyIdleSeconds: residencyIdleSeconds ?? self.residencyIdleSeconds,
            residentGigabytes: residentGigabytes ?? self.residentGigabytes,
            runtimeID: runtimeID ?? self.runtimeID,
            thinking: thinking ?? self.thinking,
            timeoutSeconds: timeoutSeconds ?? self.timeoutSeconds
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

/// The capability profile product logic asks for. 'local' is not a capability but a policy:
/// a surface that must never leave this machine even if a cloud escape hatch is later
/// enabled.
public enum ModelProfileID: String, Codable {
    case balanced = "balanced"
    case deep = "deep"
    case fast = "fast"
    case local = "local"
}

/// pinned for an always-on surface, where a ~70 s cold reload would be felt every time;
/// evictAfterUse for a rare specialist that would otherwise hold tens of gigabytes.
public enum Residency: String, Codable {
    case bounded = "bounded"
    case evictAfterUse = "evictAfterUse"
    case pinned = "pinned"
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - CerebralHelmSettingsPatch
public struct CerebralHelmSettingsPatch: Codable {
    public let changes: Changes
    public let patchID: String
    public let schemaVersion: String

    public enum CodingKeys: String, CodingKey {
        case changes
        case patchID = "patchId"
        case schemaVersion
    }

    public init(changes: Changes, patchID: String, schemaVersion: String) {
        self.changes = changes
        self.patchID = patchID
        self.schemaVersion = schemaVersion
    }
}

// MARK: CerebralHelmSettingsPatch convenience initializers and mutators

public extension CerebralHelmSettingsPatch {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CerebralHelmSettingsPatch.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        changes: Changes? = nil,
        patchID: String? = nil,
        schemaVersion: String? = nil
    ) -> CerebralHelmSettingsPatch {
        return CerebralHelmSettingsPatch(
            changes: changes ?? self.changes,
            patchID: patchID ?? self.patchID,
            schemaVersion: schemaVersion ?? self.schemaVersion
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - Changes
public struct Changes: Codable {
    public let appearance: Appearance?
    /// The user's calendar→mode mapping for the Today panel's per-mode relevance filtering
    /// (NIC-126), keyed by the calendar's stable identifier with a mode-id value. When present,
    /// replaces the stored map wholesale — an empty object clears it.
    public let calendarModeMap: [String: String]?
    public let confirmAllActions: Bool?
    public let defaultModeID: String?
    public let extensions: [String: JSONAny]?
    public let hotkeys: Hotkeys?
    public let knowledge: Knowledge?
    public let modeColors: [String: String]?
    public let stocks: Stocks?
    public let workspace: Workspace?

    public enum CodingKeys: String, CodingKey {
        case appearance, calendarModeMap, confirmAllActions
        case defaultModeID = "defaultModeId"
        case extensions, hotkeys, knowledge, modeColors, stocks, workspace
    }

    public init(appearance: Appearance?, calendarModeMap: [String: String]?, confirmAllActions: Bool?, defaultModeID: String?, extensions: [String: JSONAny]?, hotkeys: Hotkeys?, knowledge: Knowledge?, modeColors: [String: String]?, stocks: Stocks?, workspace: Workspace?) {
        self.appearance = appearance
        self.calendarModeMap = calendarModeMap
        self.confirmAllActions = confirmAllActions
        self.defaultModeID = defaultModeID
        self.extensions = extensions
        self.hotkeys = hotkeys
        self.knowledge = knowledge
        self.modeColors = modeColors
        self.stocks = stocks
        self.workspace = workspace
    }
}

// MARK: Changes convenience initializers and mutators

public extension Changes {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(Changes.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        appearance: Appearance?? = nil,
        calendarModeMap: [String: String]?? = nil,
        confirmAllActions: Bool?? = nil,
        defaultModeID: String?? = nil,
        extensions: [String: JSONAny]?? = nil,
        hotkeys: Hotkeys?? = nil,
        knowledge: Knowledge?? = nil,
        modeColors: [String: String]?? = nil,
        stocks: Stocks?? = nil,
        workspace: Workspace?? = nil
    ) -> Changes {
        return Changes(
            appearance: appearance ?? self.appearance,
            calendarModeMap: calendarModeMap ?? self.calendarModeMap,
            confirmAllActions: confirmAllActions ?? self.confirmAllActions,
            defaultModeID: defaultModeID ?? self.defaultModeID,
            extensions: extensions ?? self.extensions,
            hotkeys: hotkeys ?? self.hotkeys,
            knowledge: knowledge ?? self.knowledge,
            modeColors: modeColors ?? self.modeColors,
            stocks: stocks ?? self.stocks,
            workspace: workspace ?? self.workspace
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - Appearance
public struct Appearance: Codable {
    public let assistantName: String?
    public let density: Density?
    public let reducedMotion: Bool?

    public init(assistantName: String?, density: Density?, reducedMotion: Bool?) {
        self.assistantName = assistantName
        self.density = density
        self.reducedMotion = reducedMotion
    }
}

// MARK: Appearance convenience initializers and mutators

public extension Appearance {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(Appearance.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        assistantName: String?? = nil,
        density: Density?? = nil,
        reducedMotion: Bool?? = nil
    ) -> Appearance {
        return Appearance(
            assistantName: assistantName ?? self.assistantName,
            density: density ?? self.density,
            reducedMotion: reducedMotion ?? self.reducedMotion
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

public enum Density: String, Codable {
    case comfortable = "comfortable"
    case compact = "compact"
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - Hotkeys
public struct Hotkeys: Codable {
    public let commandPalette: String?

    public init(commandPalette: String?) {
        self.commandPalette = commandPalette
    }
}

// MARK: Hotkeys convenience initializers and mutators

public extension Hotkeys {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(Hotkeys.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        commandPalette: String?? = nil
    ) -> Hotkeys {
        return Hotkeys(
            commandPalette: commandPalette ?? self.commandPalette
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - Knowledge
public struct Knowledge: Codable {
    public let rootReference: String?

    public init(rootReference: String?) {
        self.rootReference = rootReference
    }
}

// MARK: Knowledge convenience initializers and mutators

public extension Knowledge {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(Knowledge.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        rootReference: String?? = nil
    ) -> Knowledge {
        return Knowledge(
            rootReference: rootReference ?? self.rootReference
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - Stocks
public struct Stocks: Codable {
    /// The user's tracked stock symbols for the Executive Stocks widget (NIC-128). When present,
    /// replaces the stored list wholesale — an empty array clears it. Capped so a refresh stays
    /// within the provider's rate limit.
    public let tickers: [String]?

    public init(tickers: [String]?) {
        self.tickers = tickers
    }
}

// MARK: Stocks convenience initializers and mutators

public extension Stocks {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(Stocks.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        tickers: [String]?? = nil
    ) -> Stocks {
        return Stocks(
            tickers: tickers ?? self.tickers
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - Workspace
public struct Workspace: Codable {
    public let layoutDisplayID, mainDisplayID: String?
    public let windowsStoredByMode: Bool?

    public enum CodingKeys: String, CodingKey {
        case layoutDisplayID = "layoutDisplayId"
        case mainDisplayID = "mainDisplayId"
        case windowsStoredByMode
    }

    public init(layoutDisplayID: String?, mainDisplayID: String?, windowsStoredByMode: Bool?) {
        self.layoutDisplayID = layoutDisplayID
        self.mainDisplayID = mainDisplayID
        self.windowsStoredByMode = windowsStoredByMode
    }
}

// MARK: Workspace convenience initializers and mutators

public extension Workspace {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(Workspace.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        layoutDisplayID: String?? = nil,
        mainDisplayID: String?? = nil,
        windowsStoredByMode: Bool?? = nil
    ) -> Workspace {
        return Workspace(
            layoutDisplayID: layoutDisplayID ?? self.layoutDisplayID,
            mainDisplayID: mainDisplayID ?? self.mainDisplayID,
            windowsStoredByMode: windowsStoredByMode ?? self.windowsStoredByMode
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

/// The system-managed YAML frontmatter of a durable Markdown note (FR-KNW-05). Markdown is
/// the source of truth; this is the metadata block the system reads and writes. User-added
/// frontmatter keys are preserved by the note codec and are outside this contract. Safe
/// defaults are applied when optional fields are absent, and cloudPolicy defaults to deny or
/// ask — never allow.
// MARK: - CerebralHelmNoteMetadata
public struct CerebralHelmNoteMetadata: Codable {
    /// Whether the note may be sent to a cloud provider. Defaults to deny; never defaults to
    /// allow.
    public let cloudPolicy: CloudPolicy
    public let created: Date
    /// Stable, URL/file-safe note id.
    public let id: String
    /// Note kind (e.g. note, daily, project-note, reference).
    public let kind: String
    /// Optional durable project or area this note belongs to. Modes reference these; they do not
    /// duplicate the note.
    public let project: String?
    /// Optional freshness boundary: after this instant the note is due for review.
    public let reviewAfter: Date?
    public let schemaVersion: String
    /// Defaults to private when unspecified.
    public let sensitivity: Sensitivity
    /// Defaults to active when unspecified.
    public let status: CerebralHelmNoteMetadataStatus
    public let title: String
    public let updated: Date

    public init(cloudPolicy: CloudPolicy, created: Date, id: String, kind: String, project: String?, reviewAfter: Date?, schemaVersion: String, sensitivity: Sensitivity, status: CerebralHelmNoteMetadataStatus, title: String, updated: Date) {
        self.cloudPolicy = cloudPolicy
        self.created = created
        self.id = id
        self.kind = kind
        self.project = project
        self.reviewAfter = reviewAfter
        self.schemaVersion = schemaVersion
        self.sensitivity = sensitivity
        self.status = status
        self.title = title
        self.updated = updated
    }
}

// MARK: CerebralHelmNoteMetadata convenience initializers and mutators

public extension CerebralHelmNoteMetadata {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CerebralHelmNoteMetadata.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        cloudPolicy: CloudPolicy? = nil,
        created: Date? = nil,
        id: String? = nil,
        kind: String? = nil,
        project: String?? = nil,
        reviewAfter: Date?? = nil,
        schemaVersion: String? = nil,
        sensitivity: Sensitivity? = nil,
        status: CerebralHelmNoteMetadataStatus? = nil,
        title: String? = nil,
        updated: Date? = nil
    ) -> CerebralHelmNoteMetadata {
        return CerebralHelmNoteMetadata(
            cloudPolicy: cloudPolicy ?? self.cloudPolicy,
            created: created ?? self.created,
            id: id ?? self.id,
            kind: kind ?? self.kind,
            project: project ?? self.project,
            reviewAfter: reviewAfter ?? self.reviewAfter,
            schemaVersion: schemaVersion ?? self.schemaVersion,
            sensitivity: sensitivity ?? self.sensitivity,
            status: status ?? self.status,
            title: title ?? self.title,
            updated: updated ?? self.updated
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

/// Defaults to active when unspecified.
public enum CerebralHelmNoteMetadataStatus: String, Codable {
    case active = "active"
    case archived = "archived"
    case draft = "draft"
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - CerebralHelmReferenceCatalog
public struct CerebralHelmReferenceCatalog: Codable {
    public let references: [Reference]
    public let schemaVersion: String

    public init(references: [Reference], schemaVersion: String) {
        self.references = references
        self.schemaVersion = schemaVersion
    }
}

// MARK: CerebralHelmReferenceCatalog convenience initializers and mutators

public extension CerebralHelmReferenceCatalog {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CerebralHelmReferenceCatalog.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        references: [Reference]? = nil,
        schemaVersion: String? = nil
    ) -> CerebralHelmReferenceCatalog {
        return CerebralHelmReferenceCatalog(
            references: references ?? self.references,
            schemaVersion: schemaVersion ?? self.schemaVersion
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - Reference
public struct Reference: Codable {
    public let id, label: String
    public let profile: String?
    public let target: String

    public init(id: String, label: String, profile: String?, target: String) {
        self.id = id
        self.label = label
        self.profile = profile
        self.target = target
    }
}

// MARK: Reference convenience initializers and mutators

public extension Reference {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(Reference.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        id: String? = nil,
        label: String? = nil,
        profile: String?? = nil,
        target: String? = nil
    ) -> Reference {
        return Reference(
            id: id ?? self.id,
            label: label ?? self.label,
            profile: profile ?? self.profile,
            target: target ?? self.target
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

/// The rendered form of every Report-archetype quick action (docs/quick-actions/PLAN.md). A
/// report is NOT a template — it is a typed block document, because the deterministic
/// composer that writes it today will be replaced by a model later. The pipeline is
/// providers -> Assembler -> Snapshot -> Composer -> ReportDocument -> Renderer; only the
/// Composer changes when the model lands, and the Renderer never does. A model streaming
/// blocks into the renderer is visually identical to the deterministic reveal, which is why
/// the future conversation surface is not a new surface.
///
/// Blocks are intentionally a FLAT shape keyed by `kind` rather than a discriminated union:
/// a union would make adding a block kind a breaking contract change, and the renderer
/// already has to survive a malformed block once a model writes these. The renderer skips
/// any block whose kind it does not know, or whose fields for that kind are absent — a
/// report never crashes the dashboard.
///
/// Codegen note: quicktype ignores `$defs` titles and names generated types from PROPERTY
/// names, so a generic property name here mints (or steals) a generic type name across the
/// whole shared contracts module. Hence the kind-prefixed field names on a block.
// MARK: - CerebralHelmReportDocument
public struct CerebralHelmReportDocument: Codable {
    /// The document's blocks, in render order. `maxItems` is a SAFETY BOUND, not a design limit:
    /// real reports use well under 30, and the cap exists because a grammar-constrained model
    /// composing this document will happily emit valid blocks forever. Measured: one composition
    /// produced 123 blocks — `line` and `metric` alternating, every optional field filled,
    /// nonsense values throughout — until it exhausted the context and truncated mid-token,
    /// which is UNPARSEABLE rather than merely invalid. Every array and string in this schema is
    /// bounded for the same reason. A grammar enforces exactly what the schema says and removes
    /// the model's incentive to be plausible, so anything left unbounded here becomes reachable
    /// there.
    public let blocks: [Block]
    /// Whether this report was composed from a fetch the reader can repeat. The region shows a
    /// refresh control only for a report that says so — offering one on a document composed from
    /// ambient state would promise something it cannot do.
    public let refreshable: Bool?
    /// The quick-action id this document was composed for, so the renderer can key its reveal
    /// and the region can title itself.
    public let reportID: String
    public let schemaVersion: String

    public enum CodingKeys: String, CodingKey {
        case blocks, refreshable
        case reportID = "reportId"
        case schemaVersion
    }

    public init(blocks: [Block], refreshable: Bool?, reportID: String, schemaVersion: String) {
        self.blocks = blocks
        self.refreshable = refreshable
        self.reportID = reportID
        self.schemaVersion = schemaVersion
    }
}

// MARK: CerebralHelmReportDocument convenience initializers and mutators

public extension CerebralHelmReportDocument {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CerebralHelmReportDocument.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        blocks: [Block]? = nil,
        refreshable: Bool?? = nil,
        reportID: String? = nil,
        schemaVersion: String? = nil
    ) -> CerebralHelmReportDocument {
        return CerebralHelmReportDocument(
            blocks: blocks ?? self.blocks,
            refreshable: refreshable ?? self.refreshable,
            reportID: reportID ?? self.reportID,
            schemaVersion: schemaVersion ?? self.schemaVersion
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

/// One block of a report. `blockKind` selects which of the optional fields carry meaning;
/// the renderer reads only those and ignores the rest. Field names are deliberately
/// kind-prefixed (`greetingSize`, `lineEmphasis`, `metricTone`, `listItems`,
/// `reportAction`): they say which kind they belong to, which a flat block needs anyway, AND
/// they keep codegen from minting single-word type names like `Kind` / `Tone` / `Size` in
/// the shared namespace. That is not cosmetic — a bare `kind` here renamed the pre-existing
/// layout `Kind` enum and broke LayoutWorkflowSynthesizer, and a bare `action` did the same
/// to the mode-apply `Action` type.
// MARK: - Block
public struct Block: Codable {
    public let blockKind: BlockKind
    public let greetingSize: GreetingSize?
    public let label: String?
    /// How many rows show before the reader expands. Absent shows all of them.
    public let leaderboardPreview: Int?
    /// A `leaderboard` block's ranked field, complete rather than truncated:
    /// `leaderboardPreview` decides how many show, so expanding needs no second fetch.
    public let leaderboardRows: [LeaderboardRow]?
    /// `strong` uses weight, never color — inside a report, color means actionable.
    public let lineEmphasis: LineEmphasis?
    public let listItems: [ListItem]?
    public let metricTone: MetricTone?
    /// A clickable destination inside a report. It is NEVER a URL — it names a registered quick
    /// action, resolved through the dispatch registry. Two reasons this is non-negotiable:
    /// opening a destination in a specific Chrome profile is a profile-scoped reference
    /// (NIC-151), not an href; and once a model composes the document, every clickable thing in
    /// it is a model-chosen destination, so a raw href would let the model — or content it
    /// summarized — point anywhere. Params are untrusted, so the target tool builds its
    /// destination host-side (the `google.search` pattern: the host is fixed, only the query
    /// varies).
    public let reportAction: PurpleReportAction?
    public let reportActions: [ReportActionElement]?
    /// A `scoreboard` block's two sides, away first.
    public let scoreboardSides: [ScoreboardSide]?
    public let text: String?
    public let value: String?

    public init(blockKind: BlockKind, greetingSize: GreetingSize?, label: String?, leaderboardPreview: Int?, leaderboardRows: [LeaderboardRow]?, lineEmphasis: LineEmphasis?, listItems: [ListItem]?, metricTone: MetricTone?, reportAction: PurpleReportAction?, reportActions: [ReportActionElement]?, scoreboardSides: [ScoreboardSide]?, text: String?, value: String?) {
        self.blockKind = blockKind
        self.greetingSize = greetingSize
        self.label = label
        self.leaderboardPreview = leaderboardPreview
        self.leaderboardRows = leaderboardRows
        self.lineEmphasis = lineEmphasis
        self.listItems = listItems
        self.metricTone = metricTone
        self.reportAction = reportAction
        self.reportActions = reportActions
        self.scoreboardSides = scoreboardSides
        self.text = text
        self.value = value
    }
}

// MARK: Block convenience initializers and mutators

public extension Block {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(Block.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        blockKind: BlockKind? = nil,
        greetingSize: GreetingSize?? = nil,
        label: String?? = nil,
        leaderboardPreview: Int?? = nil,
        leaderboardRows: [LeaderboardRow]?? = nil,
        lineEmphasis: LineEmphasis?? = nil,
        listItems: [ListItem]?? = nil,
        metricTone: MetricTone?? = nil,
        reportAction: PurpleReportAction?? = nil,
        reportActions: [ReportActionElement]?? = nil,
        scoreboardSides: [ScoreboardSide]?? = nil,
        text: String?? = nil,
        value: String?? = nil
    ) -> Block {
        return Block(
            blockKind: blockKind ?? self.blockKind,
            greetingSize: greetingSize ?? self.greetingSize,
            label: label ?? self.label,
            leaderboardPreview: leaderboardPreview ?? self.leaderboardPreview,
            leaderboardRows: leaderboardRows ?? self.leaderboardRows,
            lineEmphasis: lineEmphasis ?? self.lineEmphasis,
            listItems: listItems ?? self.listItems,
            metricTone: metricTone ?? self.metricTone,
            reportAction: reportAction ?? self.reportAction,
            reportActions: reportActions ?? self.reportActions,
            scoreboardSides: scoreboardSides ?? self.scoreboardSides,
            text: text ?? self.text,
            value: value ?? self.value
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

public enum BlockKind: String, Codable {
    case checklist = "checklist"
    case count = "count"
    case empty = "empty"
    case greeting = "greeting"
    case leaderboard = "leaderboard"
    case line = "line"
    case list = "list"
    case metric = "metric"
    case proposal = "proposal"
    case scoreboard = "scoreboard"
}

public enum GreetingSize: String, Codable {
    case hero = "hero"
    case standard = "standard"
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - LeaderboardRow
public struct LeaderboardRow: Codable {
    public let rowName: String
    /// Displayed position ('T4'). Absent on a finished or unranked field.
    public let rowPosition: String?
    public let rowScore: String
    /// Holes played, only while a round is in progress.
    public let rowThru: String?

    public init(rowName: String, rowPosition: String?, rowScore: String, rowThru: String?) {
        self.rowName = rowName
        self.rowPosition = rowPosition
        self.rowScore = rowScore
        self.rowThru = rowThru
    }
}

// MARK: LeaderboardRow convenience initializers and mutators

public extension LeaderboardRow {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(LeaderboardRow.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        rowName: String? = nil,
        rowPosition: String?? = nil,
        rowScore: String? = nil,
        rowThru: String?? = nil
    ) -> LeaderboardRow {
        return LeaderboardRow(
            rowName: rowName ?? self.rowName,
            rowPosition: rowPosition ?? self.rowPosition,
            rowScore: rowScore ?? self.rowScore,
            rowThru: rowThru ?? self.rowThru
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

/// `strong` uses weight, never color — inside a report, color means actionable.
public enum LineEmphasis: String, Codable {
    case muted = "muted"
    case normal = "normal"
    case strong = "strong"
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - ListItem
public struct ListItem: Codable {
    public let color: String?
    public let meta: String?
    /// A clickable destination inside a report. It is NEVER a URL — it names a registered quick
    /// action, resolved through the dispatch registry. Two reasons this is non-negotiable:
    /// opening a destination in a specific Chrome profile is a profile-scoped reference
    /// (NIC-151), not an href; and once a model composes the document, every clickable thing in
    /// it is a model-chosen destination, so a raw href would let the model — or content it
    /// summarized — point anywhere. Params are untrusted, so the target tool builds its
    /// destination host-side (the `google.search` pattern: the host is fixed, only the query
    /// varies).
    public let reportAction: ListItemReportAction?
    /// Only meaningful on a `checklist` block — the streaming variant of a list. `skipped` is
    /// deliberately NOT a failure: a check the user never configured, or one held back because
    /// probing it would spend a small daily quota, is neither passing nor broken, and rendering
    /// it as either would make the checklist lie in one direction or the other.
    public let status: ListItemStatus?
    public let text: String

    public init(color: String?, meta: String?, reportAction: ListItemReportAction?, status: ListItemStatus?, text: String) {
        self.color = color
        self.meta = meta
        self.reportAction = reportAction
        self.status = status
        self.text = text
    }
}

// MARK: ListItem convenience initializers and mutators

public extension ListItem {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(ListItem.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        color: String?? = nil,
        meta: String?? = nil,
        reportAction: ListItemReportAction?? = nil,
        status: ListItemStatus?? = nil,
        text: String? = nil
    ) -> ListItem {
        return ListItem(
            color: color ?? self.color,
            meta: meta ?? self.meta,
            reportAction: reportAction ?? self.reportAction,
            status: status ?? self.status,
            text: text ?? self.text
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

/// A clickable destination inside a report. It is NEVER a URL — it names a registered quick
/// action, resolved through the dispatch registry. Two reasons this is non-negotiable:
/// opening a destination in a specific Chrome profile is a profile-scoped reference
/// (NIC-151), not an href; and once a model composes the document, every clickable thing in
/// it is a model-chosen destination, so a raw href would let the model — or content it
/// summarized — point anywhere. Params are untrusted, so the target tool builds its
/// destination host-side (the `google.search` pattern: the host is fixed, only the query
/// varies).
// MARK: - ListItemReportAction
public struct ListItemReportAction: Codable {
    public let action: String
    public let params: [String: JSONAny]?

    public init(action: String, params: [String: JSONAny]?) {
        self.action = action
        self.params = params
    }
}

// MARK: ListItemReportAction convenience initializers and mutators

public extension ListItemReportAction {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(ListItemReportAction.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        action: String? = nil,
        params: [String: JSONAny]?? = nil
    ) -> ListItemReportAction {
        return ListItemReportAction(
            action: action ?? self.action,
            params: params ?? self.params
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

/// Only meaningful on a `checklist` block — the streaming variant of a list. `skipped` is
/// deliberately NOT a failure: a check the user never configured, or one held back because
/// probing it would spend a small daily quota, is neither passing nor broken, and rendering
/// it as either would make the checklist lie in one direction or the other.
public enum ListItemStatus: String, Codable {
    case failed = "failed"
    case passed = "passed"
    case pending = "pending"
    case running = "running"
    case skipped = "skipped"
}

public enum MetricTone: String, Codable {
    case critical = "critical"
    case neutral = "neutral"
    case positive = "positive"
    case warning = "warning"
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

/// A clickable destination inside a report. It is NEVER a URL — it names a registered quick
/// action, resolved through the dispatch registry. Two reasons this is non-negotiable:
/// opening a destination in a specific Chrome profile is a profile-scoped reference
/// (NIC-151), not an href; and once a model composes the document, every clickable thing in
/// it is a model-chosen destination, so a raw href would let the model — or content it
/// summarized — point anywhere. Params are untrusted, so the target tool builds its
/// destination host-side (the `google.search` pattern: the host is fixed, only the query
/// varies).
// MARK: - PurpleReportAction
public struct PurpleReportAction: Codable {
    public let action: String
    public let params: [String: JSONAny]?

    public init(action: String, params: [String: JSONAny]?) {
        self.action = action
        self.params = params
    }
}

// MARK: PurpleReportAction convenience initializers and mutators

public extension PurpleReportAction {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(PurpleReportAction.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        action: String? = nil,
        params: [String: JSONAny]?? = nil
    ) -> PurpleReportAction {
        return PurpleReportAction(
            action: action ?? self.action,
            params: params ?? self.params
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

/// A clickable destination inside a report. It is NEVER a URL — it names a registered quick
/// action, resolved through the dispatch registry. Two reasons this is non-negotiable:
/// opening a destination in a specific Chrome profile is a profile-scoped reference
/// (NIC-151), not an href; and once a model composes the document, every clickable thing in
/// it is a model-chosen destination, so a raw href would let the model — or content it
/// summarized — point anywhere. Params are untrusted, so the target tool builds its
/// destination host-side (the `google.search` pattern: the host is fixed, only the query
/// varies).
// MARK: - ReportActionElement
public struct ReportActionElement: Codable {
    public let action: String
    public let params: [String: JSONAny]?

    public init(action: String, params: [String: JSONAny]?) {
        self.action = action
        self.params = params
    }
}

// MARK: ReportActionElement convenience initializers and mutators

public extension ReportActionElement {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(ReportActionElement.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        action: String? = nil,
        params: [String: JSONAny]?? = nil
    ) -> ReportActionElement {
        return ReportActionElement(
            action: action ?? self.action,
            params: params ?? self.params
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

/// One side of a team game. Carries the team's own colour so a scoreboard can look like one
/// without fetching a logo.
// MARK: - ScoreboardSide
public struct ScoreboardSide: Codable {
    public let sideAbbreviation: String
    /// Bare hex, no leading '#', as the provider supplies it.
    public let sideColor: String?
    public let sideIsHome: Bool?
    public let sideName, sideRecord: String?
    public let sideScore: String

    public init(sideAbbreviation: String, sideColor: String?, sideIsHome: Bool?, sideName: String?, sideRecord: String?, sideScore: String) {
        self.sideAbbreviation = sideAbbreviation
        self.sideColor = sideColor
        self.sideIsHome = sideIsHome
        self.sideName = sideName
        self.sideRecord = sideRecord
        self.sideScore = sideScore
    }
}

// MARK: ScoreboardSide convenience initializers and mutators

public extension ScoreboardSide {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(ScoreboardSide.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        sideAbbreviation: String? = nil,
        sideColor: String?? = nil,
        sideIsHome: Bool?? = nil,
        sideName: String?? = nil,
        sideRecord: String?? = nil,
        sideScore: String? = nil
    ) -> ScoreboardSide {
        return ScoreboardSide(
            sideAbbreviation: sideAbbreviation ?? self.sideAbbreviation,
            sideColor: sideColor ?? self.sideColor,
            sideIsHome: sideIsHome ?? self.sideIsHome,
            sideName: sideName ?? self.sideName,
            sideRecord: sideRecord ?? self.sideRecord,
            sideScore: sideScore ?? self.sideScore
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - CerebralHelmAppOpenInput
public struct CerebralHelmAppOpenInput: Codable {
    /// The id of a CONFIGURED application reference, from the app reference catalog — not an
    /// application's display name, bundle identifier, or filesystem path. Valid ids are supplied
    /// by the caller's reference catalog; there is no way to derive one from the user's words
    /// alone. If the user names an app that does not resolve to a known id, ask which one they
    /// mean rather than guessing an id — an invented id fails, and a wrong one opens the wrong
    /// application.
    public let appID: String

    public enum CodingKeys: String, CodingKey {
        case appID = "appId"
    }

    public init(appID: String) {
        self.appID = appID
    }
}

// MARK: CerebralHelmAppOpenInput convenience initializers and mutators

public extension CerebralHelmAppOpenInput {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CerebralHelmAppOpenInput.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        appID: String? = nil
    ) -> CerebralHelmAppOpenInput {
        return CerebralHelmAppOpenInput(
            appID: appID ?? self.appID
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - CerebralHelmAppOpenOutput
public struct CerebralHelmAppOpenOutput: Codable {
    public let alreadyRunning: Bool
    public let appID: String
    public let launched: Bool

    public enum CodingKeys: String, CodingKey {
        case alreadyRunning
        case appID = "appId"
        case launched
    }

    public init(alreadyRunning: Bool, appID: String, launched: Bool) {
        self.alreadyRunning = alreadyRunning
        self.appID = appID
        self.launched = launched
    }
}

// MARK: CerebralHelmAppOpenOutput convenience initializers and mutators

public extension CerebralHelmAppOpenOutput {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CerebralHelmAppOpenOutput.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        alreadyRunning: Bool? = nil,
        appID: String? = nil,
        launched: Bool? = nil
    ) -> CerebralHelmAppOpenOutput {
        return CerebralHelmAppOpenOutput(
            alreadyRunning: alreadyRunning ?? self.alreadyRunning,
            appID: appID ?? self.appID,
            launched: launched ?? self.launched
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

/// No input: this tool quits CerebralHelm itself. It deliberately takes no target, so it can
/// never be pointed at another application (that is `apps.quitall`, which in turn excludes
/// the host).
// MARK: - CerebralHelmAppQuitInput
public struct CerebralHelmAppQuitInput: Codable {

    public init() {
    }
}

// MARK: CerebralHelmAppQuitInput convenience initializers and mutators

public extension CerebralHelmAppQuitInput {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CerebralHelmAppQuitInput.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
    ) -> CerebralHelmAppQuitInput {
        return CerebralHelmAppQuitInput(
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

/// Reports that termination was requested, not that it completed — the process is on its way
/// out, so nothing downstream can observe a later status.
// MARK: - CerebralHelmAppQuitOutput
public struct CerebralHelmAppQuitOutput: Codable {
    public let status: CerebralHelmAppQuitOutputStatus

    public init(status: CerebralHelmAppQuitOutputStatus) {
        self.status = status
    }
}

// MARK: CerebralHelmAppQuitOutput convenience initializers and mutators

public extension CerebralHelmAppQuitOutput {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CerebralHelmAppQuitOutput.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        status: CerebralHelmAppQuitOutputStatus? = nil
    ) -> CerebralHelmAppQuitOutput {
        return CerebralHelmAppQuitOutput(
            status: status ?? self.status
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

public enum CerebralHelmAppQuitOutputStatus: String, Codable {
    case quitting = "quitting"
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - CerebralHelmAppsListInput
public struct CerebralHelmAppsListInput: Codable {
    /// Whether to return each application's icon as a base64-encoded PNG alongside its name and
    /// bundle id. Omitted means `true`, which attaches an image payload for every installed
    /// application - pass `false` unless the caller is actually drawing them, since the encoded
    /// icons are large and carry nothing a caller can read.
    public let includeIcons: Bool?

    public init(includeIcons: Bool?) {
        self.includeIcons = includeIcons
    }
}

// MARK: CerebralHelmAppsListInput convenience initializers and mutators

public extension CerebralHelmAppsListInput {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CerebralHelmAppsListInput.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        includeIcons: Bool?? = nil
    ) -> CerebralHelmAppsListInput {
        return CerebralHelmAppsListInput(
            includeIcons: includeIcons ?? self.includeIcons
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - CerebralHelmAppsListOutput
public struct CerebralHelmAppsListOutput: Codable {
    public let apps: [App]
    public let truncated: Bool

    public init(apps: [App], truncated: Bool) {
        self.apps = apps
        self.truncated = truncated
    }
}

// MARK: CerebralHelmAppsListOutput convenience initializers and mutators

public extension CerebralHelmAppsListOutput {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CerebralHelmAppsListOutput.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        apps: [App]? = nil,
        truncated: Bool? = nil
    ) -> CerebralHelmAppsListOutput {
        return CerebralHelmAppsListOutput(
            apps: apps ?? self.apps,
            truncated: truncated ?? self.truncated
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - App
public struct App: Codable {
    public let bundleID: String
    public let iconPNG: String?
    public let name: String

    public enum CodingKeys: String, CodingKey {
        case bundleID = "bundleId"
        case iconPNG = "iconPng"
        case name
    }

    public init(bundleID: String, iconPNG: String?, name: String) {
        self.bundleID = bundleID
        self.iconPNG = iconPNG
        self.name = name
    }
}

// MARK: App convenience initializers and mutators

public extension App {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(App.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        bundleID: String? = nil,
        iconPNG: String?? = nil,
        name: String? = nil
    ) -> App {
        return App(
            bundleID: bundleID ?? self.bundleID,
            iconPNG: iconPNG ?? self.iconPNG,
            name: name ?? self.name
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - CerebralHelmAppsQuitAllInput
public struct CerebralHelmAppsQuitAllInput: Codable {

    public init() {
    }
}

// MARK: CerebralHelmAppsQuitAllInput convenience initializers and mutators

public extension CerebralHelmAppsQuitAllInput {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CerebralHelmAppsQuitAllInput.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
    ) -> CerebralHelmAppsQuitAllInput {
        return CerebralHelmAppsQuitAllInput(
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - CerebralHelmAppsQuitAllOutput
public struct CerebralHelmAppsQuitAllOutput: Codable {
    public let bundleIDS: [String]
    public let status: CerebralHelmAppsQuitAllOutputStatus

    public enum CodingKeys: String, CodingKey {
        case bundleIDS = "bundleIds"
        case status
    }

    public init(bundleIDS: [String], status: CerebralHelmAppsQuitAllOutputStatus) {
        self.bundleIDS = bundleIDS
        self.status = status
    }
}

// MARK: CerebralHelmAppsQuitAllOutput convenience initializers and mutators

public extension CerebralHelmAppsQuitAllOutput {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CerebralHelmAppsQuitAllOutput.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        bundleIDS: [String]? = nil,
        status: CerebralHelmAppsQuitAllOutputStatus? = nil
    ) -> CerebralHelmAppsQuitAllOutput {
        return CerebralHelmAppsQuitAllOutput(
            bundleIDS: bundleIDS ?? self.bundleIDS,
            status: status ?? self.status
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

public enum CerebralHelmAppsQuitAllOutputStatus: String, Codable {
    case none = "none"
    case quit = "quit"
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

/// Creates one event in the user's calendar. `startsAt`/`endsAt` are LOCAL WALL-CLOCK ISO
/// strings (`2026-08-03T14:00:00`), not UTC instants — the same convention the calendar read
/// side uses (NIC-126), so a time the user typed into a form means the time they meant. The
/// adapter resolves them in the host's time zone.
// MARK: - CerebralHelmCalendarCreateEventInput
public struct CerebralHelmCalendarCreateEventInput: Codable {
    /// Which calendar to write to. Omitted uses the host's default calendar — never a guess at
    /// which one the user meant.
    public let calendarID: String?
    /// Local wall-clock end time in the same format as `startsAt`, and after it. When the user
    /// gave a duration rather than an end time, add it to the start; when they gave neither, a
    /// one-hour default is reasonable.
    public let endsAt: String
    /// Where the event takes place, in the user's own words - a room, an address, a meeting
    /// link. Omit unless they said one; a plausible-looking invented location is worse than an
    /// empty field.
    public let location: String?
    /// Longer detail stored on the event body - an agenda, a link, whatever the user asked to be
    /// recorded. Omit when there is nothing beyond the title; restating the title here adds
    /// nothing.
    public let notes: String?
    /// Local wall-clock start time, `YYYY-MM-DDTHH:MM` (seconds optional). NOT UTC and never
    /// carries a timezone offset or trailing `Z` — the time the user said is the time that is
    /// meant, and the host resolves it in its own zone. If the user gave a relative time
    /// ("tomorrow at noon") resolve it against the current local date; if the date is genuinely
    /// unclear, ask rather than guessing.
    public let startsAt: String
    /// The event's title, as it will appear in the calendar.
    public let title: String

    public enum CodingKeys: String, CodingKey {
        case calendarID = "calendarId"
        case endsAt, location, notes, startsAt, title
    }

    public init(calendarID: String?, endsAt: String, location: String?, notes: String?, startsAt: String, title: String) {
        self.calendarID = calendarID
        self.endsAt = endsAt
        self.location = location
        self.notes = notes
        self.startsAt = startsAt
        self.title = title
    }
}

// MARK: CerebralHelmCalendarCreateEventInput convenience initializers and mutators

public extension CerebralHelmCalendarCreateEventInput {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CerebralHelmCalendarCreateEventInput.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        calendarID: String?? = nil,
        endsAt: String? = nil,
        location: String?? = nil,
        notes: String?? = nil,
        startsAt: String? = nil,
        title: String? = nil
    ) -> CerebralHelmCalendarCreateEventInput {
        return CerebralHelmCalendarCreateEventInput(
            calendarID: calendarID ?? self.calendarID,
            endsAt: endsAt ?? self.endsAt,
            location: location ?? self.location,
            notes: notes ?? self.notes,
            startsAt: startsAt ?? self.startsAt,
            title: title ?? self.title
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - CerebralHelmCalendarCreateEventOutput
public struct CerebralHelmCalendarCreateEventOutput: Codable {
    /// The calendar it landed in, so the result can say where it went rather than just that it
    /// worked. Omitted when the store does not report one.
    public let calendarTitle: String?
    /// The created event's identifier in the host calendar store.
    public let eventID: String

    public enum CodingKeys: String, CodingKey {
        case calendarTitle
        case eventID = "eventId"
    }

    public init(calendarTitle: String?, eventID: String) {
        self.calendarTitle = calendarTitle
        self.eventID = eventID
    }
}

// MARK: CerebralHelmCalendarCreateEventOutput convenience initializers and mutators

public extension CerebralHelmCalendarCreateEventOutput {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CerebralHelmCalendarCreateEventOutput.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        calendarTitle: String?? = nil,
        eventID: String? = nil
    ) -> CerebralHelmCalendarCreateEventOutput {
        return CerebralHelmCalendarCreateEventOutput(
            calendarTitle: calendarTitle ?? self.calendarTitle,
            eventID: eventID ?? self.eventID
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - CerebralHelmConfirmationDisclosure
public struct CerebralHelmConfirmationDisclosure: Codable {
    public let accountOrService: String?
    public let actionSummary: String
    public let arguments: [Argument]
    public let choices: Choices
    public let commandID: String
    public let dataLeavingDevice: DataLeavingDevice
    public let destination: String?
    public let executionNotice: ExecutionNotice
    public let expiresAt: Date
    public let id: String
    public let invalidation: Invalidation
    public let planHash: String
    public let policyReason: String
    public let reversibility: Reversibility
    public let risk: Risk
    public let schemaVersion: String
    public let tool: Tool

    public enum CodingKeys: String, CodingKey {
        case accountOrService, actionSummary, arguments, choices
        case commandID = "commandId"
        case dataLeavingDevice, destination, executionNotice, expiresAt, id, invalidation, planHash, policyReason, reversibility, risk, schemaVersion, tool
    }

    public init(accountOrService: String?, actionSummary: String, arguments: [Argument], choices: Choices, commandID: String, dataLeavingDevice: DataLeavingDevice, destination: String?, executionNotice: ExecutionNotice, expiresAt: Date, id: String, invalidation: Invalidation, planHash: String, policyReason: String, reversibility: Reversibility, risk: Risk, schemaVersion: String, tool: Tool) {
        self.accountOrService = accountOrService
        self.actionSummary = actionSummary
        self.arguments = arguments
        self.choices = choices
        self.commandID = commandID
        self.dataLeavingDevice = dataLeavingDevice
        self.destination = destination
        self.executionNotice = executionNotice
        self.expiresAt = expiresAt
        self.id = id
        self.invalidation = invalidation
        self.planHash = planHash
        self.policyReason = policyReason
        self.reversibility = reversibility
        self.risk = risk
        self.schemaVersion = schemaVersion
        self.tool = tool
    }
}

// MARK: CerebralHelmConfirmationDisclosure convenience initializers and mutators

public extension CerebralHelmConfirmationDisclosure {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CerebralHelmConfirmationDisclosure.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        accountOrService: String?? = nil,
        actionSummary: String? = nil,
        arguments: [Argument]? = nil,
        choices: Choices? = nil,
        commandID: String? = nil,
        dataLeavingDevice: DataLeavingDevice? = nil,
        destination: String?? = nil,
        executionNotice: ExecutionNotice? = nil,
        expiresAt: Date? = nil,
        id: String? = nil,
        invalidation: Invalidation? = nil,
        planHash: String? = nil,
        policyReason: String? = nil,
        reversibility: Reversibility? = nil,
        risk: Risk? = nil,
        schemaVersion: String? = nil,
        tool: Tool? = nil
    ) -> CerebralHelmConfirmationDisclosure {
        return CerebralHelmConfirmationDisclosure(
            accountOrService: accountOrService ?? self.accountOrService,
            actionSummary: actionSummary ?? self.actionSummary,
            arguments: arguments ?? self.arguments,
            choices: choices ?? self.choices,
            commandID: commandID ?? self.commandID,
            dataLeavingDevice: dataLeavingDevice ?? self.dataLeavingDevice,
            destination: destination ?? self.destination,
            executionNotice: executionNotice ?? self.executionNotice,
            expiresAt: expiresAt ?? self.expiresAt,
            id: id ?? self.id,
            invalidation: invalidation ?? self.invalidation,
            planHash: planHash ?? self.planHash,
            policyReason: policyReason ?? self.policyReason,
            reversibility: reversibility ?? self.reversibility,
            risk: risk ?? self.risk,
            schemaVersion: schemaVersion ?? self.schemaVersion,
            tool: tool ?? self.tool
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - Argument
public struct Argument: Codable {
    public let name: String
    public let sensitive: Bool
    public let value: String

    public init(name: String, sensitive: Bool, value: String) {
        self.name = name
        self.sensitive = sensitive
        self.value = value
    }
}

// MARK: Argument convenience initializers and mutators

public extension Argument {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(Argument.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        name: String? = nil,
        sensitive: Bool? = nil,
        value: String? = nil
    ) -> Argument {
        return Argument(
            name: name ?? self.name,
            sensitive: sensitive ?? self.sensitive,
            value: value ?? self.value
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - Choices
public struct Choices: Codable {
    public let approve: Approve
    public let cancel: Cancel
    public let defaultFocusedChoice: DefaultFocusedChoice
    public let review: Review

    public init(approve: Approve, cancel: Cancel, defaultFocusedChoice: DefaultFocusedChoice, review: Review) {
        self.approve = approve
        self.cancel = cancel
        self.defaultFocusedChoice = defaultFocusedChoice
        self.review = review
    }
}

// MARK: Choices convenience initializers and mutators

public extension Choices {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(Choices.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        approve: Approve? = nil,
        cancel: Cancel? = nil,
        defaultFocusedChoice: DefaultFocusedChoice? = nil,
        review: Review? = nil
    ) -> Choices {
        return Choices(
            approve: approve ?? self.approve,
            cancel: cancel ?? self.cancel,
            defaultFocusedChoice: defaultFocusedChoice ?? self.defaultFocusedChoice,
            review: review ?? self.review
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - Approve
public struct Approve: Codable {
    public let label: String

    public init(label: String) {
        self.label = label
    }
}

// MARK: Approve convenience initializers and mutators

public extension Approve {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(Approve.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        label: String? = nil
    ) -> Approve {
        return Approve(
            label: label ?? self.label
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - Cancel
public struct Cancel: Codable {
    public let label: String

    public init(label: String) {
        self.label = label
    }
}

// MARK: Cancel convenience initializers and mutators

public extension Cancel {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(Cancel.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        label: String? = nil
    ) -> Cancel {
        return Cancel(
            label: label ?? self.label
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

public enum DefaultFocusedChoice: String, Codable {
    case cancel = "cancel"
    case review = "review"
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - Review
public struct Review: Codable {
    public let label: String

    public init(label: String) {
        self.label = label
    }
}

// MARK: Review convenience initializers and mutators

public extension Review {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(Review.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        label: String? = nil
    ) -> Review {
        return Review(
            label: label ?? self.label
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

public enum DataLeavingDevice: String, Codable {
    case content = "content"
    case metadataOnly = "metadata_only"
    case none = "none"
    case unknown = "unknown"
}

public enum ExecutionNotice: String, Codable {
    case executionHasNotHappenedYet = "Execution has not happened yet."
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - Invalidation
public struct Invalidation: Codable {
    public let expires, invalidAfterPlanChange, singleUseToken: Bool

    public init(expires: Bool, invalidAfterPlanChange: Bool, singleUseToken: Bool) {
        self.expires = expires
        self.invalidAfterPlanChange = invalidAfterPlanChange
        self.singleUseToken = singleUseToken
    }
}

// MARK: Invalidation convenience initializers and mutators

public extension Invalidation {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(Invalidation.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        expires: Bool? = nil,
        invalidAfterPlanChange: Bool? = nil,
        singleUseToken: Bool? = nil
    ) -> Invalidation {
        return Invalidation(
            expires: expires ?? self.expires,
            invalidAfterPlanChange: invalidAfterPlanChange ?? self.invalidAfterPlanChange,
            singleUseToken: singleUseToken ?? self.singleUseToken
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

public enum Reversibility: String, Codable {
    case notReversible = "not_reversible"
    case partiallyReversible = "partially_reversible"
    case reversible = "reversible"
    case unknown = "unknown"
}

public enum Risk: String, Codable {
    case destructive = "destructive"
    case externalWrite = "external_write"
    case financial = "financial"
    case localWrite = "local_write"
    case purchaseOrBooking = "purchase_or_booking"
    case readOnly = "read_only"
    case shell = "shell"
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - Tool
public struct Tool: Codable {
    public let id: String
    public let purpose: String
    public let version: String

    public init(id: String, purpose: String, version: String) {
        self.id = id
        self.purpose = purpose
        self.version = version
    }
}

// MARK: Tool convenience initializers and mutators

public extension Tool {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(Tool.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        id: String? = nil,
        purpose: String? = nil,
        version: String? = nil
    ) -> Tool {
        return Tool(
            id: id ?? self.id,
            purpose: purpose ?? self.purpose,
            version: version ?? self.version
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - CerebralHelmCourseListInput
public struct CerebralHelmCourseListInput: Codable {
    /// Caps the returned courses, most recently written first. Omit for all of them — a school
    /// year is a handful of folders, so the cap exists for symmetry with note.list rather than
    /// because the list is ever large.
    public let courseLimit: Int?

    public init(courseLimit: Int?) {
        self.courseLimit = courseLimit
    }
}

// MARK: CerebralHelmCourseListInput convenience initializers and mutators

public extension CerebralHelmCourseListInput {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CerebralHelmCourseListInput.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        courseLimit: Int?? = nil
    ) -> CerebralHelmCourseListInput {
        return CerebralHelmCourseListInput(
            courseLimit: courseLimit ?? self.courseLimit
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - CerebralHelmCourseListOutput
public struct CerebralHelmCourseListOutput: Codable {
    /// The root-relative school folder the courses were read from, so a caller can say where
    /// they came from without knowing the convention.
    public let courseRoot: String
    public let courses: [Course]

    public init(courseRoot: String, courses: [Course]) {
        self.courseRoot = courseRoot
        self.courses = courses
    }
}

// MARK: CerebralHelmCourseListOutput convenience initializers and mutators

public extension CerebralHelmCourseListOutput {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CerebralHelmCourseListOutput.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        courseRoot: String? = nil,
        courses: [Course]? = nil
    ) -> CerebralHelmCourseListOutput {
        return CerebralHelmCourseListOutput(
            courseRoot: courseRoot ?? self.courseRoot,
            courses: courses ?? self.courses
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - Course
public struct Course: Codable {
    /// Root-relative, forward-slashed, so it can be compared directly to a note listing's folder.
    public let courseFolder: String
    /// The course as displayed and addressed — the derived code (STAT 240) where the source
    /// carried one. Also the folder's last path component.
    public let courseName: String
    /// How many notes the folder holds. Zero is a real answer: a course can exist and be empty.
    public let courseNoteCount: Int
    /// ISO-8601 of the most recently changed note in the course, absent when it holds none.
    public let courseUpdated: String?

    public init(courseFolder: String, courseName: String, courseNoteCount: Int, courseUpdated: String?) {
        self.courseFolder = courseFolder
        self.courseName = courseName
        self.courseNoteCount = courseNoteCount
        self.courseUpdated = courseUpdated
    }
}

// MARK: Course convenience initializers and mutators

public extension Course {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(Course.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        courseFolder: String? = nil,
        courseName: String? = nil,
        courseNoteCount: Int? = nil,
        courseUpdated: String?? = nil
    ) -> Course {
        return Course(
            courseFolder: courseFolder ?? self.courseFolder,
            courseName: courseName ?? self.courseName,
            courseNoteCount: courseNoteCount ?? self.courseNoteCount,
            courseUpdated: courseUpdated ?? self.courseUpdated
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - CerebralHelmCourseNoteCreateInput
public struct CerebralHelmCourseNoteCreateInput: Codable {
    /// The course to file the note under, as a human course name or code. The adapter DERIVES
    /// the folder from it inside the school root and creates it if this is the course's first
    /// note — the caller never names a folder, so a note can only ever land under the school
    /// root.
    public let noteCourse: String
    /// The note's title. It becomes the H1 and the filename's readable part; the filename is
    /// date-prefixed by the adapter so a course folder sorts chronologically on its own.
    public let noteTitle: String

    public init(noteCourse: String, noteTitle: String) {
        self.noteCourse = noteCourse
        self.noteTitle = noteTitle
    }
}

// MARK: CerebralHelmCourseNoteCreateInput convenience initializers and mutators

public extension CerebralHelmCourseNoteCreateInput {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CerebralHelmCourseNoteCreateInput.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        noteCourse: String? = nil,
        noteTitle: String? = nil
    ) -> CerebralHelmCourseNoteCreateInput {
        return CerebralHelmCourseNoteCreateInput(
            noteCourse: noteCourse ?? self.noteCourse,
            noteTitle: noteTitle ?? self.noteTitle
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - CerebralHelmCourseNoteCreateOutput
public struct CerebralHelmCourseNoteCreateOutput: Codable {
    /// The course as it was resolved — the derived code, which may differ from what was asked
    /// for.
    public let noteCourse: String
    /// False when a note of that title already existed for that day and was returned instead of
    /// being overwritten. Creating a note never clobbers one.
    public let noteCreated: Bool
    /// The note's root-relative path: the same handle note.open takes, so the caller can open
    /// what it just created without deriving a path of its own.
    public let notePath: String
    public let noteTitle: String

    public init(noteCourse: String, noteCreated: Bool, notePath: String, noteTitle: String) {
        self.noteCourse = noteCourse
        self.noteCreated = noteCreated
        self.notePath = notePath
        self.noteTitle = noteTitle
    }
}

// MARK: CerebralHelmCourseNoteCreateOutput convenience initializers and mutators

public extension CerebralHelmCourseNoteCreateOutput {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CerebralHelmCourseNoteCreateOutput.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        noteCourse: String? = nil,
        noteCreated: Bool? = nil,
        notePath: String? = nil,
        noteTitle: String? = nil
    ) -> CerebralHelmCourseNoteCreateOutput {
        return CerebralHelmCourseNoteCreateOutput(
            noteCourse: noteCourse ?? self.noteCourse,
            noteCreated: noteCreated ?? self.noteCreated,
            notePath: notePath ?? self.notePath,
            noteTitle: noteTitle ?? self.noteTitle
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - CerebralHelmGitCloneInput
public struct CerebralHelmGitCloneInput: Codable {
    /// Optional folder for the clone, relative to the projects root. Omit it and the folder is
    /// derived from the repository name. Whatever is supplied, the adapter re-checks that the
    /// resolved path stays inside the projects root, so no relative escape can place a clone
    /// elsewhere.
    public let cloneDirectory: String?
    /// The https URL of the repository to clone. The adapter refuses any other scheme, and
    /// refuses a URL carrying embedded credentials (user:token@host) so a secret can never reach
    /// the command log.
    public let repositoryURL: String

    public init(cloneDirectory: String?, repositoryURL: String) {
        self.cloneDirectory = cloneDirectory
        self.repositoryURL = repositoryURL
    }
}

// MARK: CerebralHelmGitCloneInput convenience initializers and mutators

public extension CerebralHelmGitCloneInput {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CerebralHelmGitCloneInput.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        cloneDirectory: String?? = nil,
        repositoryURL: String? = nil
    ) -> CerebralHelmGitCloneInput {
        return CerebralHelmGitCloneInput(
            cloneDirectory: cloneDirectory ?? self.cloneDirectory,
            repositoryURL: repositoryURL ?? self.repositoryURL
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - CerebralHelmGitCloneOutput
public struct CerebralHelmGitCloneOutput: Codable {
    /// The absolute path the repository was cloned to, always inside the projects root.
    public let clonedPath: String
    /// The folder name the clone landed in.
    public let clonedRepositoryName: String

    public init(clonedPath: String, clonedRepositoryName: String) {
        self.clonedPath = clonedPath
        self.clonedRepositoryName = clonedRepositoryName
    }
}

// MARK: CerebralHelmGitCloneOutput convenience initializers and mutators

public extension CerebralHelmGitCloneOutput {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CerebralHelmGitCloneOutput.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        clonedPath: String? = nil,
        clonedRepositoryName: String? = nil
    ) -> CerebralHelmGitCloneOutput {
        return CerebralHelmGitCloneOutput(
            clonedPath: clonedPath ?? self.clonedPath,
            clonedRepositoryName: clonedRepositoryName ?? self.clonedRepositoryName
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - CerebralHelmGoogleSearchInput
public struct CerebralHelmGoogleSearchInput: Codable {
    /// The search text. The adapter builds a Google search URL host-side (the host is fixed to
    /// google.com); only this query is variable, so untrusted data can never choose the
    /// destination.
    public let query: String

    public init(query: String) {
        self.query = query
    }
}

// MARK: CerebralHelmGoogleSearchInput convenience initializers and mutators

public extension CerebralHelmGoogleSearchInput {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CerebralHelmGoogleSearchInput.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        query: String? = nil
    ) -> CerebralHelmGoogleSearchInput {
        return CerebralHelmGoogleSearchInput(
            query: query ?? self.query
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - CerebralHelmGoogleSearchOutput
public struct CerebralHelmGoogleSearchOutput: Codable {
    public let opened: Bool
    public let query: String
    /// The Google search URL that was opened.
    public let resolvedURL: String

    public init(opened: Bool, query: String, resolvedURL: String) {
        self.opened = opened
        self.query = query
        self.resolvedURL = resolvedURL
    }
}

// MARK: CerebralHelmGoogleSearchOutput convenience initializers and mutators

public extension CerebralHelmGoogleSearchOutput {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CerebralHelmGoogleSearchOutput.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        opened: Bool? = nil,
        query: String? = nil,
        resolvedURL: String? = nil
    ) -> CerebralHelmGoogleSearchOutput {
        return CerebralHelmGoogleSearchOutput(
            opened: opened ?? self.opened,
            query: query ?? self.query,
            resolvedURL: resolvedURL ?? self.resolvedURL
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - CerebralHelmHookRunInput
public struct CerebralHelmHookRunInput: Codable {
    /// The id of a CONFIGURED, allowlisted hook, from the hook catalog. This is never shell
    /// text, a command line, a script path, or an executable name — the hook's contents are
    /// fixed in configuration and only its id is selected here, so no command the caller
    /// composes can be run. If the user's words do not resolve to a known hook id, ask rather
    /// than guessing.
    public let hookID: String

    public enum CodingKeys: String, CodingKey {
        case hookID = "hookId"
    }

    public init(hookID: String) {
        self.hookID = hookID
    }
}

// MARK: CerebralHelmHookRunInput convenience initializers and mutators

public extension CerebralHelmHookRunInput {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CerebralHelmHookRunInput.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        hookID: String? = nil
    ) -> CerebralHelmHookRunInput {
        return CerebralHelmHookRunInput(
            hookID: hookID ?? self.hookID
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - CerebralHelmHookRunOutput
public struct CerebralHelmHookRunOutput: Codable {
    public let durationMS: Int
    public let environment: [String: String]?
    public let exitCode: Int
    public let hookID: String
    public let stderr, stdout: String
    public let timedOut: Bool

    public enum CodingKeys: String, CodingKey {
        case durationMS = "durationMs"
        case environment, exitCode
        case hookID = "hookId"
        case stderr, stdout, timedOut
    }

    public init(durationMS: Int, environment: [String: String]?, exitCode: Int, hookID: String, stderr: String, stdout: String, timedOut: Bool) {
        self.durationMS = durationMS
        self.environment = environment
        self.exitCode = exitCode
        self.hookID = hookID
        self.stderr = stderr
        self.stdout = stdout
        self.timedOut = timedOut
    }
}

// MARK: CerebralHelmHookRunOutput convenience initializers and mutators

public extension CerebralHelmHookRunOutput {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CerebralHelmHookRunOutput.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        durationMS: Int? = nil,
        environment: [String: String]?? = nil,
        exitCode: Int? = nil,
        hookID: String? = nil,
        stderr: String? = nil,
        stdout: String? = nil,
        timedOut: Bool? = nil
    ) -> CerebralHelmHookRunOutput {
        return CerebralHelmHookRunOutput(
            durationMS: durationMS ?? self.durationMS,
            environment: environment ?? self.environment,
            exitCode: exitCode ?? self.exitCode,
            hookID: hookID ?? self.hookID,
            stderr: stderr ?? self.stderr,
            stdout: stdout ?? self.stdout,
            timedOut: timedOut ?? self.timedOut
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

/// Property names are prefixed because the code generator derives type names from property
/// names: a bare `title`/`description`/`priority` would mint or steal a generic type across
/// the whole shared module.
// MARK: - CerebralHelmLinearCreateIssueInput
public struct CerebralHelmLinearCreateIssueInput: Codable {
    /// Markdown body. Optional.
    public let issueDescription: String?
    /// Linear's priority scale: 0 none, 1 urgent, 2 high, 3 medium, 4 low.
    public let issuePriority: Int?
    /// The issue's one-line title, as it appears in Linear.
    public let issueTitle: String
    /// Optional labels. A list because Linear issues carry several, and because that is how the
    /// labels are actually used here — an issue is routinely both a category and a status.
    public let linearLabelIDs: [String]?
    /// Optional project. Must belong to the chosen team.
    public let linearProjectID: String?
    /// The Linear team the issue belongs to. Required by the API and never inferred: a workspace
    /// can have several teams, and guessing one would file the ticket somewhere the user did not
    /// choose.
    public let linearTeamID: String

    public init(issueDescription: String?, issuePriority: Int?, issueTitle: String, linearLabelIDs: [String]?, linearProjectID: String?, linearTeamID: String) {
        self.issueDescription = issueDescription
        self.issuePriority = issuePriority
        self.issueTitle = issueTitle
        self.linearLabelIDs = linearLabelIDs
        self.linearProjectID = linearProjectID
        self.linearTeamID = linearTeamID
    }
}

// MARK: CerebralHelmLinearCreateIssueInput convenience initializers and mutators

public extension CerebralHelmLinearCreateIssueInput {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CerebralHelmLinearCreateIssueInput.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        issueDescription: String?? = nil,
        issuePriority: Int?? = nil,
        issueTitle: String? = nil,
        linearLabelIDs: [String]?? = nil,
        linearProjectID: String?? = nil,
        linearTeamID: String? = nil
    ) -> CerebralHelmLinearCreateIssueInput {
        return CerebralHelmLinearCreateIssueInput(
            issueDescription: issueDescription ?? self.issueDescription,
            issuePriority: issuePriority ?? self.issuePriority,
            issueTitle: issueTitle ?? self.issueTitle,
            linearLabelIDs: linearLabelIDs ?? self.linearLabelIDs,
            linearProjectID: linearProjectID ?? self.linearProjectID,
            linearTeamID: linearTeamID ?? self.linearTeamID
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - CerebralHelmLinearCreateIssueOutput
public struct CerebralHelmLinearCreateIssueOutput: Codable {
    /// The human-readable identifier Linear assigned, e.g. NIC-176.
    public let issueIdentifier: String
    /// The issue's web URL, as returned by Linear — never constructed here.
    public let issueURL: String

    public init(issueIdentifier: String, issueURL: String) {
        self.issueIdentifier = issueIdentifier
        self.issueURL = issueURL
    }
}

// MARK: CerebralHelmLinearCreateIssueOutput convenience initializers and mutators

public extension CerebralHelmLinearCreateIssueOutput {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CerebralHelmLinearCreateIssueOutput.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        issueIdentifier: String? = nil,
        issueURL: String? = nil
    ) -> CerebralHelmLinearCreateIssueOutput {
        return CerebralHelmLinearCreateIssueOutput(
            issueIdentifier: issueIdentifier ?? self.issueIdentifier,
            issueURL: issueURL ?? self.issueURL
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - CerebralHelmMailOpenInput
public struct CerebralHelmMailOpenInput: Codable {
    /// The RFC 5322 Message-ID of the email to open, without the angle brackets. Omit to open
    /// the inbox itself. The adapter builds the mail.google.com URL host-side with the host as a
    /// literal constant — only this id varies — so untrusted data can never choose the
    /// destination.
    public let mailMessageID: String?

    public enum CodingKeys: String, CodingKey {
        case mailMessageID = "mailMessageId"
    }

    public init(mailMessageID: String?) {
        self.mailMessageID = mailMessageID
    }
}

// MARK: CerebralHelmMailOpenInput convenience initializers and mutators

public extension CerebralHelmMailOpenInput {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CerebralHelmMailOpenInput.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        mailMessageID: String?? = nil
    ) -> CerebralHelmMailOpenInput {
        return CerebralHelmMailOpenInput(
            mailMessageID: mailMessageID ?? self.mailMessageID
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - CerebralHelmMailOpenOutput
public struct CerebralHelmMailOpenOutput: Codable {
    public let mailOpened: Bool
    /// The Gmail URL that was opened.
    public let mailResolvedURL: String

    public init(mailOpened: Bool, mailResolvedURL: String) {
        self.mailOpened = mailOpened
        self.mailResolvedURL = mailResolvedURL
    }
}

// MARK: CerebralHelmMailOpenOutput convenience initializers and mutators

public extension CerebralHelmMailOpenOutput {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CerebralHelmMailOpenOutput.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        mailOpened: Bool? = nil,
        mailResolvedURL: String? = nil
    ) -> CerebralHelmMailOpenOutput {
        return CerebralHelmMailOpenOutput(
            mailOpened: mailOpened ?? self.mailOpened,
            mailResolvedURL: mailResolvedURL ?? self.mailResolvedURL
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - CerebralHelmMessagesSendInput
public struct CerebralHelmMessagesSendInput: Codable {
    /// The message text. Passed to the adapter as an argument, never interpolated into a script,
    /// so quotes and AppleScript keywords in it are data.
    public let messageBody: String
    /// How many people are in the thread, when it is a group. Disclosed because sending to nine
    /// people is a materially bigger action than sending to one (FR-SAF-04).
    public let messageGroupSize: Int?
    /// A participant handle (phone number or Apple ID) or a chat identifier, per
    /// messageTargetKind.
    public let messageTarget: String
    /// Messages can send to one person or to an existing chat. A new group cannot be assembled —
    /// the scripting dictionary's `chat` class is read-only — so a group is always an existing
    /// thread.
    public let messageTargetKind: MessageTargetKind
    /// The recipient's display name, so a confirmation can name who this is going to in words
    /// rather than as a phone number.
    public let messageTargetName: String?

    public init(messageBody: String, messageGroupSize: Int?, messageTarget: String, messageTargetKind: MessageTargetKind, messageTargetName: String?) {
        self.messageBody = messageBody
        self.messageGroupSize = messageGroupSize
        self.messageTarget = messageTarget
        self.messageTargetKind = messageTargetKind
        self.messageTargetName = messageTargetName
    }
}

// MARK: CerebralHelmMessagesSendInput convenience initializers and mutators

public extension CerebralHelmMessagesSendInput {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CerebralHelmMessagesSendInput.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        messageBody: String? = nil,
        messageGroupSize: Int?? = nil,
        messageTarget: String? = nil,
        messageTargetKind: MessageTargetKind? = nil,
        messageTargetName: String?? = nil
    ) -> CerebralHelmMessagesSendInput {
        return CerebralHelmMessagesSendInput(
            messageBody: messageBody ?? self.messageBody,
            messageGroupSize: messageGroupSize ?? self.messageGroupSize,
            messageTarget: messageTarget ?? self.messageTarget,
            messageTargetKind: messageTargetKind ?? self.messageTargetKind,
            messageTargetName: messageTargetName ?? self.messageTargetName
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

/// Messages can send to one person or to an existing chat. A new group cannot be assembled —
/// the scripting dictionary's `chat` class is read-only — so a group is always an existing
/// thread.
public enum MessageTargetKind: String, Codable {
    case chat = "chat"
    case participant = "participant"
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - CerebralHelmMessagesSendOutput
public struct CerebralHelmMessagesSendOutput: Codable {
    public let messageSent: Bool
    /// Who it went to, echoed back so the result names them rather than repeating a handle.
    public let messageTargetName: String?

    public init(messageSent: Bool, messageTargetName: String?) {
        self.messageSent = messageSent
        self.messageTargetName = messageTargetName
    }
}

// MARK: CerebralHelmMessagesSendOutput convenience initializers and mutators

public extension CerebralHelmMessagesSendOutput {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CerebralHelmMessagesSendOutput.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        messageSent: Bool? = nil,
        messageTargetName: String?? = nil
    ) -> CerebralHelmMessagesSendOutput {
        return CerebralHelmMessagesSendOutput(
            messageSent: messageSent ?? self.messageSent,
            messageTargetName: messageTargetName ?? self.messageTargetName
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - CerebralHelmModeApplyInput
public struct CerebralHelmModeApplyInput: Codable {
    /// The id of a configured mode, from the mode catalog — the working context to switch to.
    /// Modes are defined in validated configuration rather than fixed in code, so the set of
    /// valid ids comes from the caller's configuration and is not enumerable here. If the user's
    /// words do not clearly name a configured mode, ask rather than guessing.
    public let modeID: String

    public enum CodingKeys: String, CodingKey {
        case modeID = "modeId"
    }

    public init(modeID: String) {
        self.modeID = modeID
    }
}

// MARK: CerebralHelmModeApplyInput convenience initializers and mutators

public extension CerebralHelmModeApplyInput {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CerebralHelmModeApplyInput.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        modeID: String? = nil
    ) -> CerebralHelmModeApplyInput {
        return CerebralHelmModeApplyInput(
            modeID: modeID ?? self.modeID
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - CerebralHelmModeApplyOutput
public struct CerebralHelmModeApplyOutput: Codable {
    public let actions: [Action]
    public let aggregateRisk: Risk
    public let modeID: String
    public let status: CerebralHelmModeApplyOutputStatus

    public enum CodingKeys: String, CodingKey {
        case actions, aggregateRisk
        case modeID = "modeId"
        case status
    }

    public init(actions: [Action], aggregateRisk: Risk, modeID: String, status: CerebralHelmModeApplyOutputStatus) {
        self.actions = actions
        self.aggregateRisk = aggregateRisk
        self.modeID = modeID
        self.status = status
    }
}

// MARK: CerebralHelmModeApplyOutput convenience initializers and mutators

public extension CerebralHelmModeApplyOutput {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CerebralHelmModeApplyOutput.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        actions: [Action]? = nil,
        aggregateRisk: Risk? = nil,
        modeID: String? = nil,
        status: CerebralHelmModeApplyOutputStatus? = nil
    ) -> CerebralHelmModeApplyOutput {
        return CerebralHelmModeApplyOutput(
            actions: actions ?? self.actions,
            aggregateRisk: aggregateRisk ?? self.aggregateRisk,
            modeID: modeID ?? self.modeID,
            status: status ?? self.status
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - Action
public struct Action: Codable {
    public let actionID, kind: String
    public let message: String?
    public let risk: Risk
    public let status: ActionStatus

    public enum CodingKeys: String, CodingKey {
        case actionID = "actionId"
        case kind, message, risk, status
    }

    public init(actionID: String, kind: String, message: String?, risk: Risk, status: ActionStatus) {
        self.actionID = actionID
        self.kind = kind
        self.message = message
        self.risk = risk
        self.status = status
    }
}

// MARK: Action convenience initializers and mutators

public extension Action {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(Action.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        actionID: String? = nil,
        kind: String? = nil,
        message: String?? = nil,
        risk: Risk? = nil,
        status: ActionStatus? = nil
    ) -> Action {
        return Action(
            actionID: actionID ?? self.actionID,
            kind: kind ?? self.kind,
            message: message ?? self.message,
            risk: risk ?? self.risk,
            status: status ?? self.status
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

public enum ActionStatus: String, Codable {
    case failed = "failed"
    case skipped = "skipped"
    case success = "success"
    case unavailable = "unavailable"
}

public enum CerebralHelmModeApplyOutputStatus: String, Codable {
    case partialSuccess = "partial_success"
    case success = "success"
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - CerebralHelmNetworkSpeedTestInput
public struct CerebralHelmNetworkSpeedTestInput: Codable {

    public init() {
    }
}

// MARK: CerebralHelmNetworkSpeedTestInput convenience initializers and mutators

public extension CerebralHelmNetworkSpeedTestInput {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CerebralHelmNetworkSpeedTestInput.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
    ) -> CerebralHelmNetworkSpeedTestInput {
        return CerebralHelmNetworkSpeedTestInput(
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - CerebralHelmNetworkSpeedTestOutput
public struct CerebralHelmNetworkSpeedTestOutput: Codable {
    /// Measured download capacity in Mbps, when known.
    public let downloadMbps: Double?
    /// ok = both directions measured; partial = one direction only; unavailable = the test could
    /// not run.
    public let status: CerebralHelmNetworkSpeedTestOutputStatus
    /// ISO-8601 timestamp when the measurement completed.
    public let testedAt: String
    /// Measured upload capacity in Mbps, when known.
    public let uploadMbps: Double?

    public init(downloadMbps: Double?, status: CerebralHelmNetworkSpeedTestOutputStatus, testedAt: String, uploadMbps: Double?) {
        self.downloadMbps = downloadMbps
        self.status = status
        self.testedAt = testedAt
        self.uploadMbps = uploadMbps
    }
}

// MARK: CerebralHelmNetworkSpeedTestOutput convenience initializers and mutators

public extension CerebralHelmNetworkSpeedTestOutput {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CerebralHelmNetworkSpeedTestOutput.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        downloadMbps: Double?? = nil,
        status: CerebralHelmNetworkSpeedTestOutputStatus? = nil,
        testedAt: String? = nil,
        uploadMbps: Double?? = nil
    ) -> CerebralHelmNetworkSpeedTestOutput {
        return CerebralHelmNetworkSpeedTestOutput(
            downloadMbps: downloadMbps ?? self.downloadMbps,
            status: status ?? self.status,
            testedAt: testedAt ?? self.testedAt,
            uploadMbps: uploadMbps ?? self.uploadMbps
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

/// ok = both directions measured; partial = one direction only; unavailable = the test could
/// not run.
public enum CerebralHelmNetworkSpeedTestOutputStatus: String, Codable {
    case ok = "ok"
    case partial = "partial"
    case unavailable = "unavailable"
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - CerebralHelmNoteCaptureInput
public struct CerebralHelmNoteCaptureInput: Codable {
    /// The note's Markdown content. May be empty for a title-only capture.
    public let body: String
    /// A short lowercase-hyphenated classifier stored in the note's frontmatter so notes can be
    /// filtered later. The vocabulary is deliberately OPEN — there is no fixed list, and no
    /// value is rejected for being unfamiliar. Prefer reusing a kind already used elsewhere in
    /// the user's notes; when nothing more specific fits, use `note`. Never omit this or block
    /// on it: an imperfect classifier is recoverable, a failed capture loses the user's thought.
    public let kind: String
    /// Optional project slug to file the note under. Omit unless the user named a project —
    /// inventing one misfiles the note.
    public let project: String?
    /// Privacy label recorded in the note's frontmatter. It is metadata, not access control -
    /// nothing today restricts reading a note based on it. Omitted degrades to `private`, which
    /// is the right answer unless the user's own words call for another; do not judge the
    /// content's sensitivity yourself.
    public let sensitivity: Sensitivity?
    /// The note's title, used as its heading and to derive its filename. Take the user's own
    /// words where they gave a title; otherwise write a short descriptive one.
    public let title: String

    public init(body: String, kind: String, project: String?, sensitivity: Sensitivity?, title: String) {
        self.body = body
        self.kind = kind
        self.project = project
        self.sensitivity = sensitivity
        self.title = title
    }
}

// MARK: CerebralHelmNoteCaptureInput convenience initializers and mutators

public extension CerebralHelmNoteCaptureInput {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CerebralHelmNoteCaptureInput.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        body: String? = nil,
        kind: String? = nil,
        project: String?? = nil,
        sensitivity: Sensitivity?? = nil,
        title: String? = nil
    ) -> CerebralHelmNoteCaptureInput {
        return CerebralHelmNoteCaptureInput(
            body: body ?? self.body,
            kind: kind ?? self.kind,
            project: project ?? self.project,
            sensitivity: sensitivity ?? self.sensitivity,
            title: title ?? self.title
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - CerebralHelmNoteCaptureOutput
public struct CerebralHelmNoteCaptureOutput: Codable {
    public let created: Bool
    public let noteID: String
    public let path: String

    public enum CodingKeys: String, CodingKey {
        case created
        case noteID = "noteId"
        case path
    }

    public init(created: Bool, noteID: String, path: String) {
        self.created = created
        self.noteID = noteID
        self.path = path
    }
}

// MARK: CerebralHelmNoteCaptureOutput convenience initializers and mutators

public extension CerebralHelmNoteCaptureOutput {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CerebralHelmNoteCaptureOutput.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        created: Bool? = nil,
        noteID: String? = nil,
        path: String? = nil
    ) -> CerebralHelmNoteCaptureOutput {
        return CerebralHelmNoteCaptureOutput(
            created: created ?? self.created,
            noteID: noteID ?? self.noteID,
            path: path ?? self.path
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - CerebralHelmNoteListInput
public struct CerebralHelmNoteListInput: Codable {
    /// Caps the returned notes, most recently changed first. Omitted means every note under the
    /// knowledge root; the output reports whether a cap truncated the listing, so a caller is
    /// never silently shown a partial library.
    public let limit: Int?

    public init(limit: Int?) {
        self.limit = limit
    }
}

// MARK: CerebralHelmNoteListInput convenience initializers and mutators

public extension CerebralHelmNoteListInput {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CerebralHelmNoteListInput.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        limit: Int?? = nil
    ) -> CerebralHelmNoteListInput {
        return CerebralHelmNoteListInput(
            limit: limit ?? self.limit
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - CerebralHelmNoteListOutput
public struct CerebralHelmNoteListOutput: Codable {
    /// The notes on disk, most recently changed first, then by path so equal timestamps stay
    /// stable.
    public let notes: [NoteListItem]
    /// The absolute path of the knowledge root the notes were read from, so a caller can cite
    /// the source location without a second read.
    public let root: String
    /// Every note found under the root, before any limit. A caller that asks for the five most
    /// recent notes still learns how many there are, so a count is never quietly the size of its
    /// own request.
    public let total: Int
    /// Whether the requested limit cut the listing short — equivalently, `total` exceeds the
    /// length of `notes`.
    public let truncated: Bool

    public init(notes: [NoteListItem], root: String, total: Int, truncated: Bool) {
        self.notes = notes
        self.root = root
        self.total = total
        self.truncated = truncated
    }
}

// MARK: CerebralHelmNoteListOutput convenience initializers and mutators

public extension CerebralHelmNoteListOutput {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CerebralHelmNoteListOutput.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        notes: [NoteListItem]? = nil,
        root: String? = nil,
        total: Int? = nil,
        truncated: Bool? = nil
    ) -> CerebralHelmNoteListOutput {
        return CerebralHelmNoteListOutput(
            notes: notes ?? self.notes,
            root: root ?? self.root,
            total: total ?? self.total,
            truncated: truncated ?? self.truncated
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - NoteListItem
public struct NoteListItem: Codable {
    /// The containing folder relative to the knowledge root (`inbox`, `projects/atlas`), empty
    /// at the root — the durable hierarchy, for grouping by project or area.
    public let folder: String
    /// The CerebralHelm note id from frontmatter. Absent for a note authored outside
    /// CerebralHelm, which is an ordinary case, not a defect — such a note has no id and is
    /// addressed by path. Deliberately unpatterned, unlike note-search-output's noteId: a file
    /// may be named anything.
    public let noteID: String?
    /// The note's path relative to the knowledge root, forward-slashed. This is the handle:
    /// note.read takes it verbatim.
    public let path: String
    /// The project the note belongs to: its frontmatter project, else the folder beneath
    /// `projects/` that contains it.
    public let project: String?
    public let sensitivity: Sensitivity?
    /// The frontmatter title when the note declares one, else its filename.
    public let title: String
    /// ISO-8601. The frontmatter `updated` when present, else the file's modification date, so a
    /// note edited in another editor still reports when it actually changed. Absent only when
    /// neither is readable.
    public let updated: String?

    public enum CodingKeys: String, CodingKey {
        case folder
        case noteID = "noteId"
        case path, project, sensitivity, title, updated
    }

    public init(folder: String, noteID: String?, path: String, project: String?, sensitivity: Sensitivity?, title: String, updated: String?) {
        self.folder = folder
        self.noteID = noteID
        self.path = path
        self.project = project
        self.sensitivity = sensitivity
        self.title = title
        self.updated = updated
    }
}

// MARK: NoteListItem convenience initializers and mutators

public extension NoteListItem {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(NoteListItem.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        folder: String? = nil,
        noteID: String?? = nil,
        path: String? = nil,
        project: String?? = nil,
        sensitivity: Sensitivity?? = nil,
        title: String? = nil,
        updated: String?? = nil
    ) -> NoteListItem {
        return NoteListItem(
            folder: folder ?? self.folder,
            noteID: noteID ?? self.noteID,
            path: path ?? self.path,
            project: project ?? self.project,
            sensitivity: sensitivity ?? self.sensitivity,
            title: title ?? self.title,
            updated: updated ?? self.updated
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - CerebralHelmNoteOpenInput
public struct CerebralHelmNoteOpenInput: Codable {
    /// The note's path relative to the knowledge root, as reported by note.list and note.search.
    /// Root-relative and Markdown only; the knowledge service additionally resolves the path and
    /// refuses anything landing outside the root, so this pattern is a first gate, not the
    /// boundary. Named `notePath` rather than `path` because the code generator derives type
    /// names from property names, and a schema structurally identical to note-read-input would
    /// otherwise collapse into one shared type.
    public let notePath: String

    public init(notePath: String) {
        self.notePath = notePath
    }
}

// MARK: CerebralHelmNoteOpenInput convenience initializers and mutators

public extension CerebralHelmNoteOpenInput {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CerebralHelmNoteOpenInput.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        notePath: String? = nil
    ) -> CerebralHelmNoteOpenInput {
        return CerebralHelmNoteOpenInput(
            notePath: notePath ?? self.notePath
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - CerebralHelmNoteOpenOutput
public struct CerebralHelmNoteOpenOutput: Codable {
    /// Which surface received the note. `finder` is the honest fallback when nothing handles
    /// obsidian:// — the note is still revealed, so the action does something real rather than
    /// silently doing nothing. `none` accompanies noteOpened=false.
    public let noteOpenTarget: NoteOpenTarget
    /// Whether the note was actually handed to an application. False is a real answer, not a
    /// failure: it says the note exists and nothing on this machine took it.
    public let noteOpened: Bool
    /// The root-relative path that was opened, echoed so a caller can report what happened
    /// without re-deriving it.
    public let notePath: String

    public init(noteOpenTarget: NoteOpenTarget, noteOpened: Bool, notePath: String) {
        self.noteOpenTarget = noteOpenTarget
        self.noteOpened = noteOpened
        self.notePath = notePath
    }
}

// MARK: CerebralHelmNoteOpenOutput convenience initializers and mutators

public extension CerebralHelmNoteOpenOutput {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CerebralHelmNoteOpenOutput.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        noteOpenTarget: NoteOpenTarget? = nil,
        noteOpened: Bool? = nil,
        notePath: String? = nil
    ) -> CerebralHelmNoteOpenOutput {
        return CerebralHelmNoteOpenOutput(
            noteOpenTarget: noteOpenTarget ?? self.noteOpenTarget,
            noteOpened: noteOpened ?? self.noteOpened,
            notePath: notePath ?? self.notePath
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

/// Which surface received the note. `finder` is the honest fallback when nothing handles
/// obsidian:// — the note is still revealed, so the action does something real rather than
/// silently doing nothing. `none` accompanies noteOpened=false.
public enum NoteOpenTarget: String, Codable {
    case finder = "finder"
    case none = "none"
    case obsidian = "obsidian"
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - CerebralHelmNoteReadInput
public struct CerebralHelmNoteReadInput: Codable {
    /// The note's path relative to the knowledge root, as reported by note.list. Root-relative
    /// and Markdown only; the adapter additionally resolves the path and refuses anything that
    /// lands outside the knowledge root, so this pattern is a first gate, not the boundary.
    public let path: String

    public init(path: String) {
        self.path = path
    }
}

// MARK: CerebralHelmNoteReadInput convenience initializers and mutators

public extension CerebralHelmNoteReadInput {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CerebralHelmNoteReadInput.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        path: String? = nil
    ) -> CerebralHelmNoteReadInput {
        return CerebralHelmNoteReadInput(
            path: path ?? self.path
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - CerebralHelmNoteReadOutput
public struct CerebralHelmNoteReadOutput: Codable {
    /// The Markdown body, verbatim, with the frontmatter block removed. Redacted out of the
    /// operational log by the descriptor: a note body never reaches a tool_calls row.
    public let body: String
    /// The note's frontmatter exactly as parsed, including keys CerebralHelm does not write —
    /// the file is the source of truth, so nothing in it is dropped on the way out.
    public let frontmatter: [String: String]
    /// The CerebralHelm note id from frontmatter; absent for a note authored elsewhere.
    public let noteID: String?
    /// The note's path relative to the knowledge root.
    public let path: String
    /// The absolute path of the knowledge root the note was read from; joined with `path` it is
    /// the note's source location.
    public let root: String
    /// The frontmatter title when the note declares one, else its filename.
    public let title: String
    /// ISO-8601. The frontmatter `updated` when present, else the file's modification date.
    public let updated: String?

    public enum CodingKeys: String, CodingKey {
        case body, frontmatter
        case noteID = "noteId"
        case path, root, title, updated
    }

    public init(body: String, frontmatter: [String: String], noteID: String?, path: String, root: String, title: String, updated: String?) {
        self.body = body
        self.frontmatter = frontmatter
        self.noteID = noteID
        self.path = path
        self.root = root
        self.title = title
        self.updated = updated
    }
}

// MARK: CerebralHelmNoteReadOutput convenience initializers and mutators

public extension CerebralHelmNoteReadOutput {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CerebralHelmNoteReadOutput.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        body: String? = nil,
        frontmatter: [String: String]? = nil,
        noteID: String?? = nil,
        path: String? = nil,
        root: String? = nil,
        title: String? = nil,
        updated: String?? = nil
    ) -> CerebralHelmNoteReadOutput {
        return CerebralHelmNoteReadOutput(
            body: body ?? self.body,
            frontmatter: frontmatter ?? self.frontmatter,
            noteID: noteID ?? self.noteID,
            path: path ?? self.path,
            root: root ?? self.root,
            title: title ?? self.title,
            updated: updated ?? self.updated
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - CerebralHelmNoteSearchInput
public struct CerebralHelmNoteSearchInput: Codable {
    /// Caps the returned hits. Omitted means every match in the vault, which for a common word
    /// can be most of the library. Hits are ordered by note path, not by relevance, so a cap
    /// truncates alphabetically rather than keeping the best matches - the output reports
    /// `truncated`, so a caller is never silently shown a partial result.
    public let limit: Int?
    /// Free text matched against note titles, metadata, and Markdown content. Use the user's own
    /// search terms; this is a literal text match, not a semantic one, so paraphrasing the
    /// user's wording reduces the chance of a hit.
    public let query: String

    public init(limit: Int?, query: String) {
        self.limit = limit
        self.query = query
    }
}

// MARK: CerebralHelmNoteSearchInput convenience initializers and mutators

public extension CerebralHelmNoteSearchInput {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CerebralHelmNoteSearchInput.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        limit: Int?? = nil,
        query: String? = nil
    ) -> CerebralHelmNoteSearchInput {
        return CerebralHelmNoteSearchInput(
            limit: limit ?? self.limit,
            query: query ?? self.query
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - CerebralHelmNoteSearchOutput
public struct CerebralHelmNoteSearchOutput: Codable {
    public let results: [Result]
    public let truncated: Bool

    public init(results: [Result], truncated: Bool) {
        self.results = results
        self.truncated = truncated
    }
}

// MARK: CerebralHelmNoteSearchOutput convenience initializers and mutators

public extension CerebralHelmNoteSearchOutput {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CerebralHelmNoteSearchOutput.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        results: [Result]? = nil,
        truncated: Bool? = nil
    ) -> CerebralHelmNoteSearchOutput {
        return CerebralHelmNoteSearchOutput(
            results: results ?? self.results,
            truncated: truncated ?? self.truncated
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - Result
public struct Result: Codable {
    public let excerpt: String
    public let freshness: Freshness?
    public let noteID: String
    public let path: String
    public let sensitivity: Sensitivity?
    public let title, updated: String

    public enum CodingKeys: String, CodingKey {
        case excerpt, freshness
        case noteID = "noteId"
        case path, sensitivity, title, updated
    }

    public init(excerpt: String, freshness: Freshness?, noteID: String, path: String, sensitivity: Sensitivity?, title: String, updated: String) {
        self.excerpt = excerpt
        self.freshness = freshness
        self.noteID = noteID
        self.path = path
        self.sensitivity = sensitivity
        self.title = title
        self.updated = updated
    }
}

// MARK: Result convenience initializers and mutators

public extension Result {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(Result.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        excerpt: String? = nil,
        freshness: Freshness?? = nil,
        noteID: String? = nil,
        path: String? = nil,
        sensitivity: Sensitivity?? = nil,
        title: String? = nil,
        updated: String? = nil
    ) -> Result {
        return Result(
            excerpt: excerpt ?? self.excerpt,
            freshness: freshness ?? self.freshness,
            noteID: noteID ?? self.noteID,
            path: path ?? self.path,
            sensitivity: sensitivity ?? self.sensitivity,
            title: title ?? self.title,
            updated: updated ?? self.updated
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

public enum Freshness: String, Codable {
    case aging = "aging"
    case fresh = "fresh"
    case stale = "stale"
    case unknown = "unknown"
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - CerebralHelmProjectOpenInput
public struct CerebralHelmProjectOpenInput: Codable {
    /// Absolute path of the repository directory to open in the configured editor. The adapter
    /// constrains it to the projects root; a path outside is denied.
    public let repoPath: String

    public init(repoPath: String) {
        self.repoPath = repoPath
    }
}

// MARK: CerebralHelmProjectOpenInput convenience initializers and mutators

public extension CerebralHelmProjectOpenInput {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CerebralHelmProjectOpenInput.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        repoPath: String? = nil
    ) -> CerebralHelmProjectOpenInput {
        return CerebralHelmProjectOpenInput(
            repoPath: repoPath ?? self.repoPath
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - CerebralHelmProjectOpenOutput
public struct CerebralHelmProjectOpenOutput: Codable {
    public let opened: Bool
    public let repoPath: String

    public init(opened: Bool, repoPath: String) {
        self.opened = opened
        self.repoPath = repoPath
    }
}

// MARK: CerebralHelmProjectOpenOutput convenience initializers and mutators

public extension CerebralHelmProjectOpenOutput {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CerebralHelmProjectOpenOutput.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        opened: Bool? = nil,
        repoPath: String? = nil
    ) -> CerebralHelmProjectOpenOutput {
        return CerebralHelmProjectOpenOutput(
            opened: opened ?? self.opened,
            repoPath: repoPath ?? self.repoPath
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - CerebralHelmProjectScaffoldInput
public struct CerebralHelmProjectScaffoldInput: Codable {
    /// Ordering weight for the Projects widget (higher first). Absent uses the shipped
    /// template's default.
    public let projectImportance: Int?
    /// Optional folder to create it in, relative to the projects root. The adapter joins the
    /// name onto it and re-checks that the result stays inside that root.
    public let projectLocation: String?
    /// The project's display name, which is also its folder name. The adapter refuses a name
    /// containing a path separator rather than silently mangling it into nested folders.
    public let projectName: String
    /// Optional one-line summary, written into the PROJECT.md descriptor.
    public let projectSummary: String?

    public init(projectImportance: Int?, projectLocation: String?, projectName: String, projectSummary: String?) {
        self.projectImportance = projectImportance
        self.projectLocation = projectLocation
        self.projectName = projectName
        self.projectSummary = projectSummary
    }
}

// MARK: CerebralHelmProjectScaffoldInput convenience initializers and mutators

public extension CerebralHelmProjectScaffoldInput {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CerebralHelmProjectScaffoldInput.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        projectImportance: Int?? = nil,
        projectLocation: String?? = nil,
        projectName: String? = nil,
        projectSummary: String?? = nil
    ) -> CerebralHelmProjectScaffoldInput {
        return CerebralHelmProjectScaffoldInput(
            projectImportance: projectImportance ?? self.projectImportance,
            projectLocation: projectLocation ?? self.projectLocation,
            projectName: projectName ?? self.projectName,
            projectSummary: projectSummary ?? self.projectSummary
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - CerebralHelmProjectScaffoldOutput
public struct CerebralHelmProjectScaffoldOutput: Codable {
    /// The absolute path of the PROJECT.md written into it.
    public let projectDescriptorPath: String
    /// The absolute path of the created project folder, always inside the projects root.
    public let projectPath: String

    public init(projectDescriptorPath: String, projectPath: String) {
        self.projectDescriptorPath = projectDescriptorPath
        self.projectPath = projectPath
    }
}

// MARK: CerebralHelmProjectScaffoldOutput convenience initializers and mutators

public extension CerebralHelmProjectScaffoldOutput {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CerebralHelmProjectScaffoldOutput.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        projectDescriptorPath: String? = nil,
        projectPath: String? = nil
    ) -> CerebralHelmProjectScaffoldOutput {
        return CerebralHelmProjectScaffoldOutput(
            projectDescriptorPath: projectDescriptorPath ?? self.projectDescriptorPath,
            projectPath: projectPath ?? self.projectPath
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - CerebralHelmSpotifyControlInput
public struct CerebralHelmSpotifyControlInput: Codable {
    /// The playback command to send to the user's active Spotify device: resume, pause, skip
    /// forward, or skip back.
    public let action: SpotifyPlaybackAction

    public init(action: SpotifyPlaybackAction) {
        self.action = action
    }
}

// MARK: CerebralHelmSpotifyControlInput convenience initializers and mutators

public extension CerebralHelmSpotifyControlInput {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CerebralHelmSpotifyControlInput.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        action: SpotifyPlaybackAction? = nil
    ) -> CerebralHelmSpotifyControlInput {
        return CerebralHelmSpotifyControlInput(
            action: action ?? self.action
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

/// The playback command to send to the user's active Spotify device: resume, pause, skip
/// forward, or skip back.
public enum SpotifyPlaybackAction: String, Codable {
    case next = "next"
    case pause = "pause"
    case play = "play"
    case previous = "previous"
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - CerebralHelmSpotifyControlOutput
public struct CerebralHelmSpotifyControlOutput: Codable {
    public let action: SpotifyPlaybackAction
    /// Whether there was an active Spotify device. False → nothing to control; the widget guides
    /// the user to start playback on a device.
    public let activeDevice: Bool
    /// True when Spotify accepted the command. False when there was no active device to act on.
    public let applied: Bool

    public init(action: SpotifyPlaybackAction, activeDevice: Bool, applied: Bool) {
        self.action = action
        self.activeDevice = activeDevice
        self.applied = applied
    }
}

// MARK: CerebralHelmSpotifyControlOutput convenience initializers and mutators

public extension CerebralHelmSpotifyControlOutput {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CerebralHelmSpotifyControlOutput.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        action: SpotifyPlaybackAction? = nil,
        activeDevice: Bool? = nil,
        applied: Bool? = nil
    ) -> CerebralHelmSpotifyControlOutput {
        return CerebralHelmSpotifyControlOutput(
            action: action ?? self.action,
            activeDevice: activeDevice ?? self.activeDevice,
            applied: applied ?? self.applied
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

/// Property names are prefixed because the code generator derives type names from property
/// names: a bare `name`/`description` would mint or steal a generic type across the whole
/// shared module.
// MARK: - CerebralHelmSpotifyCreatePlaylistInput
public struct CerebralHelmSpotifyCreatePlaylistInput: Codable {
    /// Optional description, as shown in Spotify clients.
    public let playlistDescription: String?
    /// Whether the playlist appears on the user's public profile. Absent means private:
    /// Spotify's own API defaults this to true, and silently publishing something to someone's
    /// profile is not a default worth inheriting.
    public let playlistIsPublic: Bool?
    /// The playlist's name, as it will appear in Spotify.
    public let playlistName: String

    public init(playlistDescription: String?, playlistIsPublic: Bool?, playlistName: String) {
        self.playlistDescription = playlistDescription
        self.playlistIsPublic = playlistIsPublic
        self.playlistName = playlistName
    }
}

// MARK: CerebralHelmSpotifyCreatePlaylistInput convenience initializers and mutators

public extension CerebralHelmSpotifyCreatePlaylistInput {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CerebralHelmSpotifyCreatePlaylistInput.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        playlistDescription: String?? = nil,
        playlistIsPublic: Bool?? = nil,
        playlistName: String? = nil
    ) -> CerebralHelmSpotifyCreatePlaylistInput {
        return CerebralHelmSpotifyCreatePlaylistInput(
            playlistDescription: playlistDescription ?? self.playlistDescription,
            playlistIsPublic: playlistIsPublic ?? self.playlistIsPublic,
            playlistName: playlistName ?? self.playlistName
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - CerebralHelmSpotifyCreatePlaylistOutput
public struct CerebralHelmSpotifyCreatePlaylistOutput: Codable {
    public let playlistID, playlistName: String
    /// Whether Spotify was opened at the new playlist. Best-effort: the playlist exists either
    /// way, so a failed open is reported rather than treated as a failed create.
    public let playlistOpened: Bool?
    /// The playlist's Spotify URL as returned by the API — never constructed here. Absent when
    /// Spotify omitted it.
    public let playlistURL: String?

    public init(playlistID: String, playlistName: String, playlistOpened: Bool?, playlistURL: String?) {
        self.playlistID = playlistID
        self.playlistName = playlistName
        self.playlistOpened = playlistOpened
        self.playlistURL = playlistURL
    }
}

// MARK: CerebralHelmSpotifyCreatePlaylistOutput convenience initializers and mutators

public extension CerebralHelmSpotifyCreatePlaylistOutput {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CerebralHelmSpotifyCreatePlaylistOutput.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        playlistID: String? = nil,
        playlistName: String? = nil,
        playlistOpened: Bool?? = nil,
        playlistURL: String?? = nil
    ) -> CerebralHelmSpotifyCreatePlaylistOutput {
        return CerebralHelmSpotifyCreatePlaylistOutput(
            playlistID: playlistID ?? self.playlistID,
            playlistName: playlistName ?? self.playlistName,
            playlistOpened: playlistOpened ?? self.playlistOpened,
            playlistURL: playlistURL ?? self.playlistURL
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - CerebralHelmSystemStatusReadInput
public struct CerebralHelmSystemStatusReadInput: Codable {
    /// Which metrics to read. Omitted or empty reads every supported metric; name a subset when
    /// the user asked about specific ones. A requested metric the host cannot supply comes back
    /// with an explicit unavailable state rather than being dropped, so a missing entry never
    /// has to be inferred.
    public let metrics: [MetricElement]?

    public init(metrics: [MetricElement]?) {
        self.metrics = metrics
    }
}

// MARK: CerebralHelmSystemStatusReadInput convenience initializers and mutators

public extension CerebralHelmSystemStatusReadInput {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CerebralHelmSystemStatusReadInput.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        metrics: [MetricElement]?? = nil
    ) -> CerebralHelmSystemStatusReadInput {
        return CerebralHelmSystemStatusReadInput(
            metrics: metrics ?? self.metrics
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

public enum MetricElement: String, Codable {
    case battery = "battery"
    case cpu = "cpu"
    case display = "display"
    case memory = "memory"
    case network = "network"
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - CerebralHelmSystemStatusReadOutput
public struct CerebralHelmSystemStatusReadOutput: Codable {
    public let metrics: [Metric]

    public init(metrics: [Metric]) {
        self.metrics = metrics
    }
}

// MARK: CerebralHelmSystemStatusReadOutput convenience initializers and mutators

public extension CerebralHelmSystemStatusReadOutput {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CerebralHelmSystemStatusReadOutput.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        metrics: [Metric]? = nil
    ) -> CerebralHelmSystemStatusReadOutput {
        return CerebralHelmSystemStatusReadOutput(
            metrics: metrics ?? self.metrics
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - Metric
public struct Metric: Codable {
    public let availability: AvailabilityEnum
    public let id: MetricElement
    public let sampledAt, unit: String?
    public let value: Double?

    public init(availability: AvailabilityEnum, id: MetricElement, sampledAt: String?, unit: String?, value: Double?) {
        self.availability = availability
        self.id = id
        self.sampledAt = sampledAt
        self.unit = unit
        self.value = value
    }
}

// MARK: Metric convenience initializers and mutators

public extension Metric {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(Metric.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        availability: AvailabilityEnum? = nil,
        id: MetricElement? = nil,
        sampledAt: String?? = nil,
        unit: String?? = nil,
        value: Double?? = nil
    ) -> Metric {
        return Metric(
            availability: availability ?? self.availability,
            id: id ?? self.id,
            sampledAt: sampledAt ?? self.sampledAt,
            unit: unit ?? self.unit,
            value: value ?? self.value
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

public enum AvailabilityEnum: String, Codable {
    case available = "available"
    case disconnected = "disconnected"
    case loading = "loading"
    case stale = "stale"
    case unavailable = "unavailable"
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - CerebralHelmToolDescriptor
public struct CerebralHelmToolDescriptor: Codable {
    public let adapterRequirements: AdapterRequirements
    public let availability: AvailabilityClass
    public let cancellable: Bool
    /// Which confirmation rule the deterministic policy engine applies to this tool.
    /// `allow_external_write_when_user_authored` is the one provenance-conditioned key: a
    /// low-stakes external write runs one-click when the user authored the arguments, and still
    /// confirms when a model proposed them. It only ever affects the `external_write` class —
    /// destructive, financial, and purchase_or_booking are never exemptible — and the
    /// stricter-only 'ask before all actions' overlay still re-arms confirmation over it.
    public let confirmationPolicyKey: ConfirmationPolicyKey
    public let id: String
    public let idempotency: Idempotency
    public let inputSchema: InputSchema
    public let logging: Logging
    public let outputSchema: OutputSchema
    public let purpose: String
    public let requiredPermissions: [String]
    public let results: [StatusElement]
    public let retry: Retry
    public let risk: Risk
    public let runtimeRiskPolicy: RuntimeRiskPolicy
    public let schemaVersion: String
    public let secretReferences: [String]
    public let timeoutMS: Int
    public let version: String

    public enum CodingKeys: String, CodingKey {
        case adapterRequirements, availability, cancellable, confirmationPolicyKey, id, idempotency, inputSchema, logging, outputSchema, purpose, requiredPermissions, results, retry, risk, runtimeRiskPolicy, schemaVersion, secretReferences
        case timeoutMS = "timeoutMs"
        case version
    }

    public init(adapterRequirements: AdapterRequirements, availability: AvailabilityClass, cancellable: Bool, confirmationPolicyKey: ConfirmationPolicyKey, id: String, idempotency: Idempotency, inputSchema: InputSchema, logging: Logging, outputSchema: OutputSchema, purpose: String, requiredPermissions: [String], results: [StatusElement], retry: Retry, risk: Risk, runtimeRiskPolicy: RuntimeRiskPolicy, schemaVersion: String, secretReferences: [String], timeoutMS: Int, version: String) {
        self.adapterRequirements = adapterRequirements
        self.availability = availability
        self.cancellable = cancellable
        self.confirmationPolicyKey = confirmationPolicyKey
        self.id = id
        self.idempotency = idempotency
        self.inputSchema = inputSchema
        self.logging = logging
        self.outputSchema = outputSchema
        self.purpose = purpose
        self.requiredPermissions = requiredPermissions
        self.results = results
        self.retry = retry
        self.risk = risk
        self.runtimeRiskPolicy = runtimeRiskPolicy
        self.schemaVersion = schemaVersion
        self.secretReferences = secretReferences
        self.timeoutMS = timeoutMS
        self.version = version
    }
}

// MARK: CerebralHelmToolDescriptor convenience initializers and mutators

public extension CerebralHelmToolDescriptor {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CerebralHelmToolDescriptor.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        adapterRequirements: AdapterRequirements? = nil,
        availability: AvailabilityClass? = nil,
        cancellable: Bool? = nil,
        confirmationPolicyKey: ConfirmationPolicyKey? = nil,
        id: String? = nil,
        idempotency: Idempotency? = nil,
        inputSchema: InputSchema? = nil,
        logging: Logging? = nil,
        outputSchema: OutputSchema? = nil,
        purpose: String? = nil,
        requiredPermissions: [String]? = nil,
        results: [StatusElement]? = nil,
        retry: Retry? = nil,
        risk: Risk? = nil,
        runtimeRiskPolicy: RuntimeRiskPolicy? = nil,
        schemaVersion: String? = nil,
        secretReferences: [String]? = nil,
        timeoutMS: Int? = nil,
        version: String? = nil
    ) -> CerebralHelmToolDescriptor {
        return CerebralHelmToolDescriptor(
            adapterRequirements: adapterRequirements ?? self.adapterRequirements,
            availability: availability ?? self.availability,
            cancellable: cancellable ?? self.cancellable,
            confirmationPolicyKey: confirmationPolicyKey ?? self.confirmationPolicyKey,
            id: id ?? self.id,
            idempotency: idempotency ?? self.idempotency,
            inputSchema: inputSchema ?? self.inputSchema,
            logging: logging ?? self.logging,
            outputSchema: outputSchema ?? self.outputSchema,
            purpose: purpose ?? self.purpose,
            requiredPermissions: requiredPermissions ?? self.requiredPermissions,
            results: results ?? self.results,
            retry: retry ?? self.retry,
            risk: risk ?? self.risk,
            runtimeRiskPolicy: runtimeRiskPolicy ?? self.runtimeRiskPolicy,
            schemaVersion: schemaVersion ?? self.schemaVersion,
            secretReferences: secretReferences ?? self.secretReferences,
            timeoutMS: timeoutMS ?? self.timeoutMS,
            version: version ?? self.version
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - AdapterRequirements
public struct AdapterRequirements: Codable {
    public let capabilities: [String]
    public let platforms: [Platform]

    public init(capabilities: [String], platforms: [Platform]) {
        self.capabilities = capabilities
        self.platforms = platforms
    }
}

// MARK: AdapterRequirements convenience initializers and mutators

public extension AdapterRequirements {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(AdapterRequirements.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        capabilities: [String]? = nil,
        platforms: [Platform]? = nil
    ) -> AdapterRequirements {
        return AdapterRequirements(
            capabilities: capabilities ?? self.capabilities,
            platforms: platforms ?? self.platforms
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

public enum Platform: String, Codable {
    case futureProvider = "future_provider"
    case macosNative = "macos_native"
    case preMACMock = "pre_mac_mock"
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - AvailabilityClass
public struct AvailabilityClass: Codable {
    public let macOS, preMAC: Bool

    public enum CodingKeys: String, CodingKey {
        case macOS
        case preMAC = "preMac"
    }

    public init(macOS: Bool, preMAC: Bool) {
        self.macOS = macOS
        self.preMAC = preMAC
    }
}

// MARK: AvailabilityClass convenience initializers and mutators

public extension AvailabilityClass {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(AvailabilityClass.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        macOS: Bool? = nil,
        preMAC: Bool? = nil
    ) -> AvailabilityClass {
        return AvailabilityClass(
            macOS: macOS ?? self.macOS,
            preMAC: preMAC ?? self.preMAC
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

/// Which confirmation rule the deterministic policy engine applies to this tool.
/// `allow_external_write_when_user_authored` is the one provenance-conditioned key: a
/// low-stakes external write runs one-click when the user authored the arguments, and still
/// confirms when a model proposed them. It only ever affects the `external_write` class —
/// destructive, financial, and purchase_or_booking are never exemptible — and the
/// stricter-only 'ask before all actions' overlay still re-arms confirmation over it.
public enum ConfirmationPolicyKey: String, Codable {
    case allowExternalWriteWhenUserAuthored = "allow_external_write_when_user_authored"
    case allowReadWithoutConfirmation = "allow_read_without_confirmation"
    case confirmDestructive = "confirm_destructive"
    case confirmExternalWrite = "confirm_external_write"
    case confirmFinancial = "confirm_financial"
    case confirmHighestPlannedAction = "confirm_highest_planned_action"
    case confirmLocalWrite = "confirm_local_write"
    case confirmPurchaseOrBooking = "confirm_purchase_or_booking"
    case confirmShell = "confirm_shell"
}

public enum Idempotency: String, Codable {
    case idempotent = "idempotent"
    case idempotentWithKey = "idempotent_with_key"
    case nonIdempotent = "non_idempotent"
    case unknown = "unknown"
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - InputSchema
public struct InputSchema: Codable {
    public let schemaID: String
    public let schemaVersion: String

    public enum CodingKeys: String, CodingKey {
        case schemaID = "schemaId"
        case schemaVersion
    }

    public init(schemaID: String, schemaVersion: String) {
        self.schemaID = schemaID
        self.schemaVersion = schemaVersion
    }
}

// MARK: InputSchema convenience initializers and mutators

public extension InputSchema {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(InputSchema.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        schemaID: String? = nil,
        schemaVersion: String? = nil
    ) -> InputSchema {
        return InputSchema(
            schemaID: schemaID ?? self.schemaID,
            schemaVersion: schemaVersion ?? self.schemaVersion
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - Logging
public struct Logging: Codable {
    public let redactionPaths: [String]
    public let retention: Retention

    public init(redactionPaths: [String], retention: Retention) {
        self.redactionPaths = redactionPaths
        self.retention = retention
    }
}

// MARK: Logging convenience initializers and mutators

public extension Logging {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(Logging.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        redactionPaths: [String]? = nil,
        retention: Retention? = nil
    ) -> Logging {
        return Logging(
            redactionPaths: redactionPaths ?? self.redactionPaths,
            retention: retention ?? self.retention
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

public enum Retention: String, Codable {
    case none = "none"
    case securityAudit = "security_audit"
    case standard = "standard"
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - OutputSchema
public struct OutputSchema: Codable {
    public let schemaID: String
    public let schemaVersion: String

    public enum CodingKeys: String, CodingKey {
        case schemaID = "schemaId"
        case schemaVersion
    }

    public init(schemaID: String, schemaVersion: String) {
        self.schemaID = schemaID
        self.schemaVersion = schemaVersion
    }
}

// MARK: OutputSchema convenience initializers and mutators

public extension OutputSchema {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(OutputSchema.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        schemaID: String? = nil,
        schemaVersion: String? = nil
    ) -> OutputSchema {
        return OutputSchema(
            schemaID: schemaID ?? self.schemaID,
            schemaVersion: schemaVersion ?? self.schemaVersion
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

public enum StatusElement: String, Codable {
    case cancelled = "cancelled"
    case denied = "denied"
    case failure = "failure"
    case partialSuccess = "partial_success"
    case success = "success"
    case timeout = "timeout"
    case unavailable = "unavailable"
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - Retry
public struct Retry: Codable {
    public let maxAttempts: Int
    public let strategy: Strategy

    public init(maxAttempts: Int, strategy: Strategy) {
        self.maxAttempts = maxAttempts
        self.strategy = strategy
    }
}

// MARK: Retry convenience initializers and mutators

public extension Retry {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(Retry.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        maxAttempts: Int? = nil,
        strategy: Strategy? = nil
    ) -> Retry {
        return Retry(
            maxAttempts: maxAttempts ?? self.maxAttempts,
            strategy: strategy ?? self.strategy
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

public enum Strategy: String, Codable {
    case exponential = "exponential"
    case fixed = "fixed"
    case none = "none"
}

public enum RuntimeRiskPolicy: String, Codable {
    case descriptorRisk = "descriptor_risk"
    case highestPlannedAction = "highest_planned_action"
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - CerebralHelmToolResult
public struct CerebralHelmToolResult: Codable {
    public let adapterID: String
    public let completedAt: Date
    public let durationMS: Int
    public let error: CerebralHelmToolResultError?
    public let redactedInput, redactedOutput: [String: JSONAny]
    public let schemaVersion: String
    public let startedAt: Date
    public let status: StatusElement
    public let toolID: String
    public let toolVersion: String

    public enum CodingKeys: String, CodingKey {
        case adapterID = "adapterId"
        case completedAt
        case durationMS = "durationMs"
        case error, redactedInput, redactedOutput, schemaVersion, startedAt, status
        case toolID = "toolId"
        case toolVersion
    }

    public init(adapterID: String, completedAt: Date, durationMS: Int, error: CerebralHelmToolResultError?, redactedInput: [String: JSONAny], redactedOutput: [String: JSONAny], schemaVersion: String, startedAt: Date, status: StatusElement, toolID: String, toolVersion: String) {
        self.adapterID = adapterID
        self.completedAt = completedAt
        self.durationMS = durationMS
        self.error = error
        self.redactedInput = redactedInput
        self.redactedOutput = redactedOutput
        self.schemaVersion = schemaVersion
        self.startedAt = startedAt
        self.status = status
        self.toolID = toolID
        self.toolVersion = toolVersion
    }
}

// MARK: CerebralHelmToolResult convenience initializers and mutators

public extension CerebralHelmToolResult {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CerebralHelmToolResult.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        adapterID: String? = nil,
        completedAt: Date? = nil,
        durationMS: Int? = nil,
        error: CerebralHelmToolResultError?? = nil,
        redactedInput: [String: JSONAny]? = nil,
        redactedOutput: [String: JSONAny]? = nil,
        schemaVersion: String? = nil,
        startedAt: Date? = nil,
        status: StatusElement? = nil,
        toolID: String? = nil,
        toolVersion: String? = nil
    ) -> CerebralHelmToolResult {
        return CerebralHelmToolResult(
            adapterID: adapterID ?? self.adapterID,
            completedAt: completedAt ?? self.completedAt,
            durationMS: durationMS ?? self.durationMS,
            error: error ?? self.error,
            redactedInput: redactedInput ?? self.redactedInput,
            redactedOutput: redactedOutput ?? self.redactedOutput,
            schemaVersion: schemaVersion ?? self.schemaVersion,
            startedAt: startedAt ?? self.startedAt,
            status: status ?? self.status,
            toolID: toolID ?? self.toolID,
            toolVersion: toolVersion ?? self.toolVersion
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - CerebralHelmToolResultError
public struct CerebralHelmToolResultError: Codable {
    public let category: Category
    public let code: String
    public let details: [String: JSONAny]?
    public let message: String
    public let remediation: String?

    public init(category: Category, code: String, details: [String: JSONAny]?, message: String, remediation: String?) {
        self.category = category
        self.code = code
        self.details = details
        self.message = message
        self.remediation = remediation
    }
}

// MARK: CerebralHelmToolResultError convenience initializers and mutators

public extension CerebralHelmToolResultError {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CerebralHelmToolResultError.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        category: Category? = nil,
        code: String? = nil,
        details: [String: JSONAny]?? = nil,
        message: String? = nil,
        remediation: String?? = nil
    ) -> CerebralHelmToolResultError {
        return CerebralHelmToolResultError(
            category: category ?? self.category,
            code: code ?? self.code,
            details: details ?? self.details,
            message: message ?? self.message,
            remediation: remediation ?? self.remediation
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - CerebralHelmURLOpenInput
public struct CerebralHelmURLOpenInput: Codable {
    /// The id of a CONFIGURED URL reference, from the URL reference catalog — never a literal
    /// web address. To open an arbitrary https address the user supplied, use `web.open`
    /// instead; this tool only opens destinations that were configured ahead of time. If the
    /// user's words do not resolve to a known id, ask rather than guessing.
    public let urlID: String

    public enum CodingKeys: String, CodingKey {
        case urlID = "urlId"
    }

    public init(urlID: String) {
        self.urlID = urlID
    }
}

// MARK: CerebralHelmURLOpenInput convenience initializers and mutators

public extension CerebralHelmURLOpenInput {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CerebralHelmURLOpenInput.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        urlID: String? = nil
    ) -> CerebralHelmURLOpenInput {
        return CerebralHelmURLOpenInput(
            urlID: urlID ?? self.urlID
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - CerebralHelmURLOpenOutput
public struct CerebralHelmURLOpenOutput: Codable {
    public let opened: Bool
    public let resolvedURL: String
    public let surfaced: Bool
    public let urlID: String

    public enum CodingKeys: String, CodingKey {
        case opened
        case resolvedURL = "resolvedUrl"
        case surfaced
        case urlID = "urlId"
    }

    public init(opened: Bool, resolvedURL: String, surfaced: Bool, urlID: String) {
        self.opened = opened
        self.resolvedURL = resolvedURL
        self.surfaced = surfaced
        self.urlID = urlID
    }
}

// MARK: CerebralHelmURLOpenOutput convenience initializers and mutators

public extension CerebralHelmURLOpenOutput {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CerebralHelmURLOpenOutput.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        opened: Bool? = nil,
        resolvedURL: String? = nil,
        surfaced: Bool? = nil,
        urlID: String? = nil
    ) -> CerebralHelmURLOpenOutput {
        return CerebralHelmURLOpenOutput(
            opened: opened ?? self.opened,
            resolvedURL: resolvedURL ?? self.resolvedURL,
            surfaced: surfaced ?? self.surfaced,
            urlID: urlID ?? self.urlID
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - CerebralHelmWebOpenInput
public struct CerebralHelmWebOpenInput: Codable {
    /// The absolute https web address to open in the browser. The adapter validates the scheme
    /// (https only) and a present host host-side, so an unresolvable or non-https link is
    /// refused rather than opened. Unlike url.open (which resolves a configured reference id),
    /// this opens an arbitrary destination — used for news article links — so the constraint
    /// lives in the adapter, not in an allowlist.
    public let url: String

    public init(url: String) {
        self.url = url
    }
}

// MARK: CerebralHelmWebOpenInput convenience initializers and mutators

public extension CerebralHelmWebOpenInput {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CerebralHelmWebOpenInput.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        url: String? = nil
    ) -> CerebralHelmWebOpenInput {
        return CerebralHelmWebOpenInput(
            url: url ?? self.url
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - CerebralHelmWebOpenOutput
public struct CerebralHelmWebOpenOutput: Codable {
    public let opened: Bool
    /// The https web address that was opened.
    public let url: String

    public init(opened: Bool, url: String) {
        self.opened = opened
        self.url = url
    }
}

// MARK: CerebralHelmWebOpenOutput convenience initializers and mutators

public extension CerebralHelmWebOpenOutput {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CerebralHelmWebOpenOutput.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        opened: Bool? = nil,
        url: String? = nil
    ) -> CerebralHelmWebOpenOutput {
        return CerebralHelmWebOpenOutput(
            opened: opened ?? self.opened,
            url: url ?? self.url
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

/// Arrange the main windows of configured applications into named frames (NIC-88).
/// Applications are configured references (same catalog as app.open) and frames are a fixed
/// named vocabulary — never arbitrary coordinates, paths, or executables. Usable as a
/// workflow step; the future layout mode builds on this same tool.
// MARK: - CerebralHelmWindowArrangeInput
public struct CerebralHelmWindowArrangeInput: Codable {
    /// The windows to place, one entry per application, applied in order. At most eight; an
    /// application named twice is placed twice, so list each one once.
    public let arrangement: [Arrangement]
    /// Which display the whole arrangement targets (NIC-142 layout mode). Absent or 'primary'
    /// targets the primary display; 'secondary' targets the first non-primary display, degrading
    /// to primary when none is attached. Frames resolve against the chosen display's visible
    /// area.
    public let display: Display?

    public init(arrangement: [Arrangement], display: Display?) {
        self.arrangement = arrangement
        self.display = display
    }
}

// MARK: CerebralHelmWindowArrangeInput convenience initializers and mutators

public extension CerebralHelmWindowArrangeInput {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CerebralHelmWindowArrangeInput.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        arrangement: [Arrangement]? = nil,
        display: Display?? = nil
    ) -> CerebralHelmWindowArrangeInput {
        return CerebralHelmWindowArrangeInput(
            arrangement: arrangement ?? self.arrangement,
            display: display ?? self.display
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - Arrangement
public struct Arrangement: Codable {
    /// The id of a CONFIGURED application reference, from the same catalog `app.open` uses — not
    /// a display name, bundle identifier, or path. If the user's words do not resolve to a known
    /// id, ask rather than guessing.
    public let appID: String
    /// Which region of the target display's visible area the window fills. Halves and thirds are
    /// measured against that display rather than the window's current size, and `centered` is a
    /// three-quarter-size window inset from every edge, not a move that preserves the window's
    /// size. Only these named frames are accepted; arbitrary coordinates are not.
    public let frame: Frame

    public enum CodingKeys: String, CodingKey {
        case appID = "appId"
        case frame
    }

    public init(appID: String, frame: Frame) {
        self.appID = appID
        self.frame = frame
    }
}

// MARK: Arrangement convenience initializers and mutators

public extension Arrangement {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(Arrangement.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        appID: String? = nil,
        frame: Frame? = nil
    ) -> Arrangement {
        return Arrangement(
            appID: appID ?? self.appID,
            frame: frame ?? self.frame
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

/// Per-entry arrangement results (NIC-88): apps that are not running or do not expose a
/// controllable window report partial results, never a silent skip or a fabricated success.
// MARK: - CerebralHelmWindowArrangeOutput
public struct CerebralHelmWindowArrangeOutput: Codable {
    public let entries: [Entry]
    public let status: CerebralHelmWindowArrangeOutputStatus

    public init(entries: [Entry], status: CerebralHelmWindowArrangeOutputStatus) {
        self.entries = entries
        self.status = status
    }
}

// MARK: CerebralHelmWindowArrangeOutput convenience initializers and mutators

public extension CerebralHelmWindowArrangeOutput {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CerebralHelmWindowArrangeOutput.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        entries: [Entry]? = nil,
        status: CerebralHelmWindowArrangeOutputStatus? = nil
    ) -> CerebralHelmWindowArrangeOutput {
        return CerebralHelmWindowArrangeOutput(
            entries: entries ?? self.entries,
            status: status ?? self.status
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - Entry
public struct Entry: Codable {
    public let appID, frame: String
    public let message: String?
    public let status: EntryStatus

    public enum CodingKeys: String, CodingKey {
        case appID = "appId"
        case frame, message, status
    }

    public init(appID: String, frame: String, message: String?, status: EntryStatus) {
        self.appID = appID
        self.frame = frame
        self.message = message
        self.status = status
    }
}

// MARK: Entry convenience initializers and mutators

public extension Entry {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(Entry.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        appID: String? = nil,
        frame: String? = nil,
        message: String?? = nil,
        status: EntryStatus? = nil
    ) -> Entry {
        return Entry(
            appID: appID ?? self.appID,
            frame: frame ?? self.frame,
            message: message ?? self.message,
            status: status ?? self.status
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

public enum EntryStatus: String, Codable {
    case arranged = "arranged"
    case failed = "failed"
    case notRunning = "not_running"
    case unknownApp = "unknown_app"
    case unsupported = "unsupported"
}

public enum CerebralHelmWindowArrangeOutputStatus: String, Codable {
    case arranged = "arranged"
    case partial = "partial"
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - CerebralHelmYouTubeSearchInput
public struct CerebralHelmYouTubeSearchInput: Codable {
    /// The search text. The adapter builds a YouTube results URL host-side (the host is fixed to
    /// youtube.com); only this query is variable, so untrusted data can never choose the
    /// destination. Named distinctly from google.search's `query` because the code generator
    /// derives type names from property names, and two structurally identical schemas would
    /// otherwise collapse into one shared type.
    public let youtubeQuery: String

    public init(youtubeQuery: String) {
        self.youtubeQuery = youtubeQuery
    }
}

// MARK: CerebralHelmYouTubeSearchInput convenience initializers and mutators

public extension CerebralHelmYouTubeSearchInput {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CerebralHelmYouTubeSearchInput.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        youtubeQuery: String? = nil
    ) -> CerebralHelmYouTubeSearchInput {
        return CerebralHelmYouTubeSearchInput(
            youtubeQuery: youtubeQuery ?? self.youtubeQuery
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - CerebralHelmYouTubeSearchOutput
public struct CerebralHelmYouTubeSearchOutput: Codable {
    public let youtubeOpened: Bool
    public let youtubeQuery: String
    /// The YouTube results URL that was opened.
    public let youtubeResolvedURL: String

    public init(youtubeOpened: Bool, youtubeQuery: String, youtubeResolvedURL: String) {
        self.youtubeOpened = youtubeOpened
        self.youtubeQuery = youtubeQuery
        self.youtubeResolvedURL = youtubeResolvedURL
    }
}

// MARK: CerebralHelmYouTubeSearchOutput convenience initializers and mutators

public extension CerebralHelmYouTubeSearchOutput {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CerebralHelmYouTubeSearchOutput.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        youtubeOpened: Bool? = nil,
        youtubeQuery: String? = nil,
        youtubeResolvedURL: String? = nil
    ) -> CerebralHelmYouTubeSearchOutput {
        return CerebralHelmYouTubeSearchOutput(
            youtubeOpened: youtubeOpened ?? self.youtubeOpened,
            youtubeQuery: youtubeQuery ?? self.youtubeQuery,
            youtubeResolvedURL: youtubeResolvedURL ?? self.youtubeResolvedURL
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

/// An ordered, linear, deterministic 1..N-step plan of tool invocations, resolved by the
/// action planner (NIC-38). A quickAction id and a mode application both resolve to this
/// same artifact; a single-step action is simply N=1. Step inputs are resolved statically
/// (literal values and reference-catalog ids) and validated against each tool's input schema
/// at resolve time. MVP scope is intentionally narrow: there is no data flow between steps
/// (a step never consumes a prior step's output), and no branching, conditional, or
/// model-driven steps. A capability a workflow lacks is added as a new tool, never as new
/// planner logic.
// MARK: - CerebralHelmWorkflowDefinition
public struct CerebralHelmWorkflowDefinition: Codable {
    public let extensions: [String: JSONAny]?
    public let id: String
    public let label: String
    public let schemaVersion: String
    public let steps: [Step]

    public init(extensions: [String: JSONAny]?, id: String, label: String, schemaVersion: String, steps: [Step]) {
        self.extensions = extensions
        self.id = id
        self.label = label
        self.schemaVersion = schemaVersion
        self.steps = steps
    }
}

// MARK: CerebralHelmWorkflowDefinition convenience initializers and mutators

public extension CerebralHelmWorkflowDefinition {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(CerebralHelmWorkflowDefinition.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        extensions: [String: JSONAny]?? = nil,
        id: String? = nil,
        label: String? = nil,
        schemaVersion: String? = nil,
        steps: [Step]? = nil
    ) -> CerebralHelmWorkflowDefinition {
        return CerebralHelmWorkflowDefinition(
            extensions: extensions ?? self.extensions,
            id: id ?? self.id,
            label: label ?? self.label,
            schemaVersion: schemaVersion ?? self.schemaVersion,
            steps: steps ?? self.steps
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// Generated by scripts/generate-contracts.mjs.

// Do not edit by hand; edit packages/contracts/schemas instead.

// MARK: - Step
public struct Step: Codable {
    public let id: String
    /// Static input/reference bindings for this step. Deep validation is deferred to resolve
    /// time, where the planner checks this object against the step tool's input schema
    /// (descriptors authoritative). MVP: resolved only from literal values and reference-catalog
    /// ids, never from another step's output.
    public let input: [String: JSONAny]?
    public let label: String?
    public let tool: String

    public init(id: String, input: [String: JSONAny]?, label: String?, tool: String) {
        self.id = id
        self.input = input
        self.label = label
        self.tool = tool
    }
}

// MARK: Step convenience initializers and mutators

public extension Step {
    init(data: Data) throws {
        self = try newJSONDecoder().decode(Step.self, from: data)
    }

    init(_ json: String, using encoding: String.Encoding = .utf8) throws {
        guard let data = json.data(using: encoding) else {
            throw NSError(domain: "JSONDecoding", code: 0, userInfo: nil)
        }
        try self.init(data: data)
    }

    init(fromURL url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    func with(
        id: String? = nil,
        input: [String: JSONAny]?? = nil,
        label: String?? = nil,
        tool: String? = nil
    ) -> Step {
        return Step(
            id: id ?? self.id,
            input: input ?? self.input,
            label: label ?? self.label,
            tool: tool ?? self.tool
        )
    }

    func jsonData() throws -> Data {
        return try newJSONEncoder().encode(self)
    }

    func jsonString(encoding: String.Encoding = .utf8) throws -> String? {
        return String(data: try self.jsonData(), encoding: encoding)
    }
}

// MARK: - Helper functions for creating encoders and decoders

func newJSONDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        if let date = generatedContractsISO8601Date(from: raw) {
            return date
        }
        throw DecodingError.dataCorrupted(
            DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Invalid ISO-8601 timestamp: \(raw)"
            )
        )
    }
    return decoder
}

func newJSONEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .custom { date, encoder in
        var container = encoder.singleValueContainer()
        try container.encode(generatedContractsISO8601String(from: date))
    }
    return encoder
}

// ISO-8601 conversion helpers that accept timestamps with or without
// fractional seconds and always emit fractional seconds. Formatters are
// created per call so the @Sendable custom coding closures capture nothing
// (ISO8601DateFormatter is not Sendable under strict concurrency).
private func generatedContractsISO8601Date(from raw: String) -> Date? {
    let withFraction = ISO8601DateFormatter()
    withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = withFraction.date(from: raw) {
        return date
    }
    let plain = ISO8601DateFormatter()
    plain.formatOptions = [.withInternetDateTime]
    return plain.date(from: raw)
}

private func generatedContractsISO8601String(from date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
}

// MARK: - Encode/decode helpers

public class JSONNull: Codable, Hashable {

    public static func == (lhs: JSONNull, rhs: JSONNull) -> Bool {
            return true
    }

    public func hash(into hasher: inout Hasher) {}

    public init() {}

    public required init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if !container.decodeNil() {
                    throw DecodingError.typeMismatch(JSONNull.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Wrong type for JSONNull"))
            }
    }

    public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encodeNil()
    }
}

final class JSONCodingKey: CodingKey {
    let key: String

    required init?(intValue: Int) {
            return nil
    }

    required init?(stringValue: String) {
            key = stringValue
    }

    var intValue: Int? {
            return nil
    }

    var stringValue: String {
            return key
    }
}

public class JSONAny: Codable {

    public let value: Any

    static func decodingError(forCodingPath codingPath: [CodingKey]) -> DecodingError {
            let context = DecodingError.Context(codingPath: codingPath, debugDescription: "Cannot decode JSONAny")
            return DecodingError.typeMismatch(JSONAny.self, context)
    }

    static func encodingError(forValue value: Any, codingPath: [CodingKey]) -> EncodingError {
            let context = EncodingError.Context(codingPath: codingPath, debugDescription: "Cannot encode JSONAny")
            return EncodingError.invalidValue(value, context)
    }

    static func decode(from container: SingleValueDecodingContainer) throws -> Any {
            if let value = try? container.decode(Bool.self) {
                    return value
            }
            if let value = try? container.decode(Int64.self) {
                    return value
            }
            if let value = try? container.decode(Double.self) {
                    return value
            }
            if let value = try? container.decode(String.self) {
                    return value
            }
            if container.decodeNil() {
                    return JSONNull()
            }
            throw decodingError(forCodingPath: container.codingPath)
    }

    static func decode(from container: inout UnkeyedDecodingContainer) throws -> Any {
            if let value = try? container.decode(Bool.self) {
                    return value
            }
            if let value = try? container.decode(Int64.self) {
                    return value
            }
            if let value = try? container.decode(Double.self) {
                    return value
            }
            if let value = try? container.decode(String.self) {
                    return value
            }
            if let value = try? container.decodeNil() {
                    if value {
                            return JSONNull()
                    }
            }
            if var container = try? container.nestedUnkeyedContainer() {
                    return try decodeArray(from: &container)
            }
            if var container = try? container.nestedContainer(keyedBy: JSONCodingKey.self) {
                    return try decodeDictionary(from: &container)
            }
            throw decodingError(forCodingPath: container.codingPath)
    }

    static func decode(from container: inout KeyedDecodingContainer<JSONCodingKey>, forKey key: JSONCodingKey) throws -> Any {
            if let value = try? container.decode(Bool.self, forKey: key) {
                    return value
            }
            if let value = try? container.decode(Int64.self, forKey: key) {
                    return value
            }
            if let value = try? container.decode(Double.self, forKey: key) {
                    return value
            }
            if let value = try? container.decode(String.self, forKey: key) {
                    return value
            }
            if let value = try? container.decodeNil(forKey: key) {
                    if value {
                            return JSONNull()
                    }
            }
            if var container = try? container.nestedUnkeyedContainer(forKey: key) {
                    return try decodeArray(from: &container)
            }
            if var container = try? container.nestedContainer(keyedBy: JSONCodingKey.self, forKey: key) {
                    return try decodeDictionary(from: &container)
            }
            throw decodingError(forCodingPath: container.codingPath)
    }

    static func decodeArray(from container: inout UnkeyedDecodingContainer) throws -> [Any] {
            var arr: [Any] = []
            while !container.isAtEnd {
                    let value = try decode(from: &container)
                    arr.append(value)
            }
            return arr
    }

    static func decodeDictionary(from container: inout KeyedDecodingContainer<JSONCodingKey>) throws -> [String: Any] {
            var dict = [String: Any]()
            for key in container.allKeys {
                    let value = try decode(from: &container, forKey: key)
                    dict[key.stringValue] = value
            }
            return dict
    }

    static func encode(to container: inout UnkeyedEncodingContainer, array: [Any]) throws {
            for value in array {
                    if let value = value as? Bool {
                            try container.encode(value)
                    } else if let value = value as? Int64 {
                            try container.encode(value)
                    } else if let value = value as? Double {
                            try container.encode(value)
                    } else if let value = value as? String {
                            try container.encode(value)
                    } else if value is JSONNull {
                            try container.encodeNil()
                    } else if let value = value as? [Any] {
                            var container = container.nestedUnkeyedContainer()
                            try encode(to: &container, array: value)
                    } else if let value = value as? [String: Any] {
                            var container = container.nestedContainer(keyedBy: JSONCodingKey.self)
                            try encode(to: &container, dictionary: value)
                    } else {
                            throw encodingError(forValue: value, codingPath: container.codingPath)
                    }
            }
    }

    static func encode(to container: inout KeyedEncodingContainer<JSONCodingKey>, dictionary: [String: Any]) throws {
            for (key, value) in dictionary {
                    let key = JSONCodingKey(stringValue: key)!
                    if let value = value as? Bool {
                            try container.encode(value, forKey: key)
                    } else if let value = value as? Int64 {
                            try container.encode(value, forKey: key)
                    } else if let value = value as? Double {
                            try container.encode(value, forKey: key)
                    } else if let value = value as? String {
                            try container.encode(value, forKey: key)
                    } else if value is JSONNull {
                            try container.encodeNil(forKey: key)
                    } else if let value = value as? [Any] {
                            var container = container.nestedUnkeyedContainer(forKey: key)
                            try encode(to: &container, array: value)
                    } else if let value = value as? [String: Any] {
                            var container = container.nestedContainer(keyedBy: JSONCodingKey.self, forKey: key)
                            try encode(to: &container, dictionary: value)
                    } else {
                            throw encodingError(forValue: value, codingPath: container.codingPath)
                    }
            }
    }

    static func encode(to container: inout SingleValueEncodingContainer, value: Any) throws {
            if let value = value as? Bool {
                    try container.encode(value)
            } else if let value = value as? Int64 {
                    try container.encode(value)
            } else if let value = value as? Double {
                    try container.encode(value)
            } else if let value = value as? String {
                    try container.encode(value)
            } else if value is JSONNull {
                    try container.encodeNil()
            } else {
                    throw encodingError(forValue: value, codingPath: container.codingPath)
            }
    }

    public required init(from decoder: Decoder) throws {
            if var arrayContainer = try? decoder.unkeyedContainer() {
                    self.value = try JSONAny.decodeArray(from: &arrayContainer)
            } else if var container = try? decoder.container(keyedBy: JSONCodingKey.self) {
                    self.value = try JSONAny.decodeDictionary(from: &container)
            } else {
                    let container = try decoder.singleValueContainer()
                    self.value = try JSONAny.decode(from: container)
            }
    }

    public func encode(to encoder: Encoder) throws {
            if let arr = self.value as? [Any] {
                    var container = encoder.unkeyedContainer()
                    try JSONAny.encode(to: &container, array: arr)
            } else if let dict = self.value as? [String: Any] {
                    var container = encoder.container(keyedBy: JSONCodingKey.self)
                    try JSONAny.encode(to: &container, dictionary: dict)
            } else {
                    var container = encoder.singleValueContainer()
                    try JSONAny.encode(to: &container, value: self.value)
            }
    }
}

