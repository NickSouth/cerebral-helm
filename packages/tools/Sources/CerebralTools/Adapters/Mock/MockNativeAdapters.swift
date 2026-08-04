import Foundation
import CerebralCore

/// Deterministic mock native adapters for the pre-Mac foundation.
///
/// Every native capability protocol has a mock here (AC-32.1). Each one applies
/// the shared ``CapabilityGate`` — capability matrix then injected fault — before
/// returning a deterministic result, so capability flags drive unavailable states
/// (AC-32.2) and any canonical failure can be reproduced (AC-32.3). No mock
/// touches a real platform API, so they remain portable and pure.

public struct MockAppCapability: AppCapability {
    public var matrix: CapabilityMatrix
    public var fault: MockFault
    public var alreadyRunningAppIDs: Set<String>

    public init(matrix: CapabilityMatrix = .allAvailable, fault: MockFault = .none, alreadyRunningAppIDs: Set<String> = []) {
        self.matrix = matrix
        self.fault = fault
        self.alreadyRunningAppIDs = alreadyRunningAppIDs
    }

    public func open(appID: String) async throws -> AppOpenResult {
        try CapabilityGate.check(CapabilityMatrix.Capability.appOpen, matrix: matrix, fault: fault, subject: appID)
        return AppOpenResult(appID: appID, launched: true, alreadyRunning: alreadyRunningAppIDs.contains(appID))
    }
}

public struct MockProjectCapability: ProjectCapability {
    public var matrix: CapabilityMatrix
    public var fault: MockFault

    public init(matrix: CapabilityMatrix = .allAvailable, fault: MockFault = .none) {
        self.matrix = matrix
        self.fault = fault
    }

    public func open(repoPath: String) async throws -> ProjectOpenResult {
        try CapabilityGate.check(CapabilityMatrix.Capability.projectOpen, matrix: matrix, fault: fault, subject: repoPath)
        return ProjectOpenResult(repoPath: repoPath, opened: true)
    }
}

public struct MockURLCapability: URLCapability {
    public var matrix: CapabilityMatrix
    public var fault: MockFault
    public var resolvedURLs: [String: String]

    public init(matrix: CapabilityMatrix = .allAvailable, fault: MockFault = .none, resolvedURLs: [String: String] = [:]) {
        self.matrix = matrix
        self.fault = fault
        self.resolvedURLs = resolvedURLs
    }

    public func open(urlID: String) async throws -> URLOpenResult {
        try CapabilityGate.check(CapabilityMatrix.Capability.urlOpen, matrix: matrix, fault: fault, subject: urlID)
        return URLOpenResult(urlID: urlID, opened: true, resolvedURL: resolvedURLs[urlID] ?? "https://example.com/\(urlID)")
    }
}

public struct MockProcessCapability: ProcessCapability {
    public var matrix: CapabilityMatrix
    public var fault: MockFault
    public var exitCode: Int
    public var stdout: String
    public var stderr: String
    public var durationMs: Int

    public init(
        matrix: CapabilityMatrix = .allAvailable,
        fault: MockFault = .none,
        exitCode: Int = 0,
        stdout: String = "",
        stderr: String = "",
        durationMs: Int = 0
    ) {
        self.matrix = matrix
        self.fault = fault
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.durationMs = durationMs
    }

    public func run(_ invocation: HookInvocation) async throws -> ProcessRunResult {
        try CapabilityGate.check(CapabilityMatrix.Capability.hookRun, matrix: matrix, fault: fault, subject: invocation.executable)
        return ProcessRunResult(
            exitCode: exitCode,
            stdout: stdout,
            stderr: stderr,
            environment: invocation.environment,
            timedOut: false,
            durationMs: durationMs
        )
    }
}

public struct MockSystemStatusCapability: SystemStatusCapability {
    public var matrix: CapabilityMatrix
    public var fault: MockFault
    /// Per-metric availability override; any metric not listed reports `.available`.
    public var perMetricAvailability: [SystemMetricID: MetricAvailability]
    public var values: [SystemMetricID: Double]

    public init(
        matrix: CapabilityMatrix = .allAvailable,
        fault: MockFault = .none,
        perMetricAvailability: [SystemMetricID: MetricAvailability] = [:],
        values: [SystemMetricID: Double] = [:]
    ) {
        self.matrix = matrix
        self.fault = fault
        self.perMetricAvailability = perMetricAvailability
        self.values = values
    }

    public func readMetrics(_ ids: [SystemMetricID]) async throws -> [SystemMetricReading] {
        try CapabilityGate.check(CapabilityMatrix.Capability.systemStatusRead, matrix: matrix, fault: fault)
        let requested = ids.isEmpty ? SystemMetricID.allCases : ids
        return requested.map { id in
            let availability = perMetricAvailability[id] ?? .available
            let value = availability == .available ? values[id] : nil
            return SystemMetricReading(id: id, availability: availability, value: value, unit: Self.unit(for: id))
        }
    }

    private static func unit(for id: SystemMetricID) -> String? {
        switch id {
        case .cpu, .memory, .battery: return "percent"
        case .network: return "mbps"
        case .display: return nil
        }
    }
}

public struct MockNetworkSpeedTestCapability: NetworkSpeedTestCapability {
    public var matrix: CapabilityMatrix
    public var fault: MockFault
    public var reading: NetworkSpeedTestReading

    public init(
        matrix: CapabilityMatrix = .allAvailable,
        fault: MockFault = .none,
        reading: NetworkSpeedTestReading = NetworkSpeedTestReading(status: .ok, downloadMbps: 240, uploadMbps: 18)
    ) {
        self.matrix = matrix
        self.fault = fault
        self.reading = reading
    }

    public func measure() async throws -> NetworkSpeedTestReading {
        try CapabilityGate.check(CapabilityMatrix.Capability.networkSpeedTest, matrix: matrix, fault: fault)
        return reading
    }
}

public struct MockSecretCapability: SecretCapability {
    public var matrix: CapabilityMatrix
    public var fault: MockFault
    public var resolvableReferences: Set<String>

    public init(matrix: CapabilityMatrix = .allAvailable, fault: MockFault = .none, resolvableReferences: Set<String> = []) {
        self.matrix = matrix
        self.fault = fault
        self.resolvableReferences = resolvableReferences
    }

    public func resolve(reference: String) async throws -> SecretResolution {
        try CapabilityGate.check(CapabilityMatrix.Capability.secret, matrix: matrix, fault: fault, subject: reference)
        return SecretResolution(reference: reference, isResolved: resolvableReferences.contains(reference))
    }
}

/// An in-memory ``SecretManaging`` for pre-Mac builds and tests (NIC-134): an actor holding a
/// dictionary, so the settings provisioning ops (`storeSecret`/`getSecretStatus`) can be
/// exercised off the real Keychain. `readValue` throws `notFound` for an unbound reference,
/// matching the Keychain adapter's contract.
public actor MockSecretStore: SecretManaging {
    private var values: [String: String]

    public init(values: [String: String] = [:]) {
        self.values = values
    }

    public func store(reference: String, value: String) async throws {
        values[reference] = value
    }

    public func readValue(reference: String) async throws -> String {
        guard let value = values[reference] else {
            throw NativeCapabilityError.notFound("No secret is stored for reference '\(reference)'.")
        }
        return value
    }

    public func delete(reference: String) async throws {
        guard values.removeValue(forKey: reference) != nil else {
            throw NativeCapabilityError.notFound("No secret is stored for reference '\(reference)'.")
        }
    }

    public func resolve(reference: String) async throws -> SecretResolution {
        SecretResolution(reference: reference, isResolved: values[reference] != nil)
    }
}

public struct MockGoogleSearchCapability: GoogleSearchCapability {
    public var matrix: CapabilityMatrix
    public var fault: MockFault

    public init(matrix: CapabilityMatrix = .allAvailable, fault: MockFault = .none) {
        self.matrix = matrix
        self.fault = fault
    }

    public func search(query: String) async throws -> GoogleSearchResult {
        try CapabilityGate.check(CapabilityMatrix.Capability.googleSearch, matrix: matrix, fault: fault, subject: query)
        return GoogleSearchResult(query: query, opened: true, resolvedURL: "https://www.google.com/search?q=\(query)")
    }
}

public struct MockMessagingCapability: MessagingCapability {
    public var matrix: CapabilityMatrix
    public var fault: MockFault

    public init(matrix: CapabilityMatrix = .allAvailable, fault: MockFault = .none) {
        self.matrix = matrix
        self.fault = fault
    }

    public func send(body: String, target: String, targetKind: String) async throws -> Bool {
        try CapabilityGate.check(CapabilityMatrix.Capability.messagesSend, matrix: matrix, fault: fault, subject: target)
        return true
    }
}

public struct MockSpotifyPlaylistCapability: SpotifyPlaylistCapability {
    public var matrix: CapabilityMatrix
    public var fault: MockFault

    public init(matrix: CapabilityMatrix = .allAvailable, fault: MockFault = .none) {
        self.matrix = matrix
        self.fault = fault
    }

    public func createPlaylist(name: String, description: String?, isPublic: Bool) async throws -> SpotifyPlaylistResult {
        try CapabilityGate.check(CapabilityMatrix.Capability.spotifyPlaylist, matrix: matrix, fault: fault, subject: name)
        return SpotifyPlaylistResult(id: "mock-playlist", name: name, url: "https://open.spotify.com/playlist/mock-playlist")
    }
}

public struct MockLinearIssueCapability: LinearIssueCapability {
    public var matrix: CapabilityMatrix
    public var fault: MockFault

    public init(matrix: CapabilityMatrix = .allAvailable, fault: MockFault = .none) {
        self.matrix = matrix
        self.fault = fault
    }

    public func createIssue(
        title: String,
        description: String?,
        teamID: String,
        projectID: String?,
        labelIDs: [String],
        priority: Int?
    ) async throws -> LinearIssueResult {
        try CapabilityGate.check(CapabilityMatrix.Capability.linearIssue, matrix: matrix, fault: fault, subject: title)
        return LinearIssueResult(
            identifier: "MOCK-1",
            url: "https://linear.app/mock/issue/MOCK-1"
        )
    }
}

public struct MockProjectScaffoldCapability: ProjectScaffoldCapability {
    public var matrix: CapabilityMatrix
    public var fault: MockFault

    public init(matrix: CapabilityMatrix = .allAvailable, fault: MockFault = .none) {
        self.matrix = matrix
        self.fault = fault
    }

    public func scaffold(
        name: String, location: String?, summary: String?, importance: Int?
    ) async throws -> ProjectScaffoldResult {
        try CapabilityGate.check(CapabilityMatrix.Capability.projectScaffold, matrix: matrix, fault: fault, subject: name)
        let path = "/mock/Projects/\(location.map { "\($0)/" } ?? "")\(name)"
        return ProjectScaffoldResult(projectPath: path, descriptorPath: path + "/PROJECT.md")
    }
}

public struct MockGitCloneCapability: GitCloneCapability {
    public var matrix: CapabilityMatrix
    public var fault: MockFault

    public init(matrix: CapabilityMatrix = .allAvailable, fault: MockFault = .none) {
        self.matrix = matrix
        self.fault = fault
    }

    public func clone(repositoryURL: String, directory: String?) async throws -> GitCloneResult {
        try CapabilityGate.check(CapabilityMatrix.Capability.gitClone, matrix: matrix, fault: fault, subject: repositoryURL)
        let name = directory ?? "repository"
        return GitCloneResult(clonedPath: "/mock/Projects/\(name)", repositoryName: name)
    }
}

public struct MockYouTubeSearchCapability: YouTubeSearchCapability {
    public var matrix: CapabilityMatrix
    public var fault: MockFault

    public init(matrix: CapabilityMatrix = .allAvailable, fault: MockFault = .none) {
        self.matrix = matrix
        self.fault = fault
    }

    public func search(query: String) async throws -> YouTubeSearchResult {
        try CapabilityGate.check(CapabilityMatrix.Capability.youtubeSearch, matrix: matrix, fault: fault, subject: query)
        return YouTubeSearchResult(
            query: query,
            opened: true,
            resolvedURL: "https://www.youtube.com/results?search_query=\(query)"
        )
    }
}

public struct MockSpotifyControlCapability: SpotifyControlCapability {
    public var matrix: CapabilityMatrix
    public var fault: MockFault

    public init(matrix: CapabilityMatrix = .allAvailable, fault: MockFault = .none) {
        self.matrix = matrix
        self.fault = fault
    }

    public func control(action: String) async throws -> SpotifyControlResult {
        try CapabilityGate.check(CapabilityMatrix.Capability.spotifyControl, matrix: matrix, fault: fault, subject: action)
        return SpotifyControlResult(action: action, applied: true, activeDevice: true)
    }
}

public struct MockWebOpenCapability: WebOpenCapability {
    public var matrix: CapabilityMatrix
    public var fault: MockFault

    public init(matrix: CapabilityMatrix = .allAvailable, fault: MockFault = .none) {
        self.matrix = matrix
        self.fault = fault
    }

    public func open(url: String) async throws -> WebOpenResult {
        try CapabilityGate.check(CapabilityMatrix.Capability.webOpen, matrix: matrix, fault: fault, subject: url)
        return WebOpenResult(url: url, opened: true)
    }
}

public struct MockWindowCapability: WindowCapability {
    public var matrix: CapabilityMatrix
    public var fault: MockFault
    public var windows: [WindowInfo]
    /// Simulated arrangement/restore outcomes by bundle id; an unlisted id is `.notRunning`.
    public var arrangeOutcomes: [String: WindowArrangeOutcome]
    /// Simulated readable main-window frames by bundle id (geometry capture).
    public var capturedFrames: [String: WindowRect]
    /// The primary display's simulated visible area (NIC-142 live capture).
    public var visibleDisplayFrame: WindowRect?

    public init(
        matrix: CapabilityMatrix = .allAvailable,
        fault: MockFault = .none,
        windows: [WindowInfo] = [],
        arrangeOutcomes: [String: WindowArrangeOutcome] = [:],
        capturedFrames: [String: WindowRect] = [:],
        visibleDisplayFrame: WindowRect? = nil
    ) {
        self.matrix = matrix
        self.fault = fault
        self.windows = windows
        self.arrangeOutcomes = arrangeOutcomes
        self.capturedFrames = capturedFrames
        self.visibleDisplayFrame = visibleDisplayFrame
    }

    public func inspect() async throws -> [WindowInfo] {
        try CapabilityGate.check(CapabilityMatrix.Capability.window, matrix: matrix, fault: fault)
        return windows
    }

    public func arrange(bundleID: String, frame: WindowFrame, display: WindowDisplay) async throws -> WindowArrangeOutcome {
        try CapabilityGate.check(CapabilityMatrix.Capability.window, matrix: matrix, fault: fault, subject: bundleID)
        return arrangeOutcomes[bundleID] ?? .notRunning
    }

    public func captureFrame(bundleID: String) async throws -> WindowRect? {
        try CapabilityGate.check(CapabilityMatrix.Capability.window, matrix: matrix, fault: fault, subject: bundleID)
        return capturedFrames[bundleID]
    }

    public func visibleFrame() async throws -> WindowRect? {
        try CapabilityGate.check(CapabilityMatrix.Capability.window, matrix: matrix, fault: fault)
        return visibleDisplayFrame
    }

    public func restoreFrame(bundleID: String, rect: WindowRect) async throws -> WindowArrangeOutcome {
        try CapabilityGate.check(CapabilityMatrix.Capability.window, matrix: matrix, fault: fault, subject: bundleID)
        return arrangeOutcomes[bundleID] ?? .notRunning
    }
}

/// Deterministic app-discovery mock (NIC-119): a fixed representative catalog,
/// gated like every mock. Icons are omitted — the honest non-Mac fallback.
public struct MockAppDiscoveryCapability: AppDiscoveryCapability {
    public var matrix: CapabilityMatrix
    public var fault: MockFault
    public var apps: [InstalledApplication]

    public init(
        matrix: CapabilityMatrix = .allAvailable,
        fault: MockFault = .none,
        apps: [InstalledApplication] = [
            InstalledApplication(bundleID: "com.apple.Safari", name: "Safari", iconPNGBase64: nil),
            InstalledApplication(bundleID: "com.apple.mail", name: "Mail", iconPNGBase64: nil),
            InstalledApplication(bundleID: "com.apple.Notes", name: "Notes", iconPNGBase64: nil),
        ]
    ) {
        self.matrix = matrix
        self.fault = fault
        self.apps = apps
    }

    public func listApplications(includeIcons: Bool) async throws -> AppDiscoveryResult {
        try CapabilityGate.check(CapabilityMatrix.Capability.appsList, matrix: matrix, fault: fault)
        return AppDiscoveryResult(apps: apps, truncated: false)
    }
}

/// Deterministic favicon mock (NIC-147): returns a fixed icon (or nothing). Favicon
/// fetch is a background UI enrichment, not a gated tool capability, so — unlike the
/// other mocks — there is no capability matrix to check; the honest non-Mac default
/// is `nil` (no favicon), which leaves the URL tile on its placeholder glyph.
public struct MockFaviconCapability: FaviconCapability {
    public var icon: Data?

    public init(icon: Data? = nil) {
        self.icon = icon
    }

    public func fetchFavicon(for url: URL) async -> Data? { icon }
}

/// Deterministic Chrome-profile-discovery mock (NIC-151): a fixed representative
/// pair of profiles. Like the favicon mock this is a background UI enrichment, not
/// a gated tool capability, so there is no capability matrix to check. Icons are
/// omitted — the honest non-Mac default (the UI falls back to a generic glyph).
public struct MockChromeProfileDiscoveryCapability: ChromeProfileDiscoveryCapability {
    public var profiles: [ChromeProfile]

    public init(
        profiles: [ChromeProfile] = [
            ChromeProfile(directory: "Default", name: "Personal", iconPNGBase64: nil),
            ChromeProfile(directory: "Profile 1", name: "Work", iconPNGBase64: nil),
        ]
    ) {
        self.profiles = profiles
    }

    public func listProfiles() async throws -> [ChromeProfile] { profiles }
}
