import Foundation
import CerebralContracts
import CerebralCore

/// The portable MVP tool handlers (NIC-33). Each strictly decodes its input
/// against the generated contract — a decode failure is a structured
/// `invalidInput` error (FR-TOL-02) — calls a portable service or mock native
/// capability, and encodes a contract-valid output. Native adapter and knowledge
/// errors are translated to `ToolHandlerError` so the executor can categorize
/// them (FR-TOL-06).

func toolHandlerError(from error: NativeCapabilityError) -> ToolHandlerError {
    switch error {
    case .unavailable: return .unavailable("The required native capability is unavailable.")
    case .permissionDenied: return .permissionDenied("The platform denied permission.")
    case let .notFound(subject): return .providerFailure("Not found: \(subject).")
    case .timedOut: return .providerFailure("The native operation timed out.")
    case .cancelled: return .providerFailure("The native operation was cancelled.")
    case let .adapterFailure(message): return .providerFailure(message)
    }
}

func toolHandlerError(from error: KnowledgeServiceError) -> ToolHandlerError {
    switch error {
    case .rootUnavailable: return .unavailable("The knowledge root is unavailable.")
    case .rootReadOnly: return .permissionDenied("The knowledge root is read-only.")
    case let .collision(message): return .providerFailure(message)
    case let .writeFailed(message): return .providerFailure(message)
    case let .noteNotFound(message): return .providerFailure(message)
    }
}

// MARK: - app.open

public struct AppOpenHandler: ToolHandler {
    public let toolID = "app.open"
    private let capability: any AppCapability

    public init(capability: any AppCapability) { self.capability = capability }

    public func execute(input: Data) async throws -> Data {
        let decoded: CerebralHelmAppOpenInput
        do { decoded = try CerebralHelmAppOpenInput(data: input) } catch {
            throw ToolHandlerError.invalidInput("app.open input does not match its contract.")
        }
        do {
            let result = try await capability.open(appID: decoded.appID)
            return try CerebralHelmAppOpenOutput(
                alreadyRunning: result.alreadyRunning,
                appID: result.appID,
                launched: result.launched
            ).jsonData()
        } catch let error as NativeCapabilityError {
            throw toolHandlerError(from: error)
        }
    }
}

// MARK: - project.open

public struct ProjectOpenHandler: ToolHandler {
    public let toolID = "project.open"
    private let capability: any ProjectCapability

    public init(capability: any ProjectCapability) { self.capability = capability }

    public func execute(input: Data) async throws -> Data {
        let decoded: CerebralHelmProjectOpenInput
        do { decoded = try CerebralHelmProjectOpenInput(data: input) } catch {
            throw ToolHandlerError.invalidInput("project.open input does not match its contract.")
        }
        do {
            let result = try await capability.open(repoPath: decoded.repoPath)
            return try CerebralHelmProjectOpenOutput(
                opened: result.opened,
                repoPath: result.repoPath
            ).jsonData()
        } catch let error as NativeCapabilityError {
            throw toolHandlerError(from: error)
        }
    }
}

// MARK: - url.open

public struct URLOpenHandler: ToolHandler {
    public let toolID = "url.open"
    private let capability: any URLCapability

    public init(capability: any URLCapability) { self.capability = capability }

    public func execute(input: Data) async throws -> Data {
        let decoded: CerebralHelmURLOpenInput
        do { decoded = try CerebralHelmURLOpenInput(data: input) } catch {
            throw ToolHandlerError.invalidInput("url.open input does not match its contract.")
        }
        do {
            let result = try await capability.open(urlID: decoded.urlID)
            return try CerebralHelmURLOpenOutput(
                opened: result.opened,
                resolvedURL: result.resolvedURL,
                surfaced: result.surfaced,
                urlID: result.urlID
            ).jsonData()
        } catch let error as NativeCapabilityError {
            throw toolHandlerError(from: error)
        }
    }
}

// MARK: - google.search

public struct GoogleSearchHandler: ToolHandler {
    public let toolID = "google.search"
    private let capability: any GoogleSearchCapability

    public init(capability: any GoogleSearchCapability) { self.capability = capability }

    public func execute(input: Data) async throws -> Data {
        let decoded: CerebralHelmGoogleSearchInput
        do { decoded = try CerebralHelmGoogleSearchInput(data: input) } catch {
            throw ToolHandlerError.invalidInput("google.search input does not match its contract.")
        }
        do {
            let result = try await capability.search(query: decoded.query)
            return try CerebralHelmGoogleSearchOutput(
                opened: result.opened,
                query: result.query,
                resolvedURL: result.resolvedURL
            ).jsonData()
        } catch let error as NativeCapabilityError {
            throw toolHandlerError(from: error)
        }
    }
}

// MARK: - messages.send

public struct MessagesSendHandler: ToolHandler {
    public let toolID = "messages.send"
    private let capability: any MessagingCapability

    public init(capability: any MessagingCapability) { self.capability = capability }

    public func execute(input: Data) async throws -> Data {
        let decoded: CerebralHelmMessagesSendInput
        do { decoded = try CerebralHelmMessagesSendInput(data: input) } catch {
            throw ToolHandlerError.invalidInput("messages.send input does not match its contract.")
        }
        do {
            let sent = try await capability.send(
                body: decoded.messageBody,
                target: decoded.messageTarget,
                targetKind: decoded.messageTargetKind.rawValue
            )
            // Never reports sent for something the adapter did not confirm.
            guard sent else {
                throw ToolHandlerError.providerFailure("Messages did not confirm the send.")
            }
            return try CerebralHelmMessagesSendOutput(
                messageSent: true,
                messageTargetName: decoded.messageTargetName
            ).jsonData()
        } catch let error as NativeCapabilityError {
            throw toolHandlerError(from: error)
        }
    }
}

// MARK: - spotify.createplaylist

public struct SpotifyCreatePlaylistHandler: ToolHandler {
    public let toolID = "spotify.createplaylist"
    private let capability: any SpotifyPlaylistCapability

    public init(capability: any SpotifyPlaylistCapability) { self.capability = capability }

    public func execute(input: Data) async throws -> Data {
        let decoded: CerebralHelmSpotifyCreatePlaylistInput
        do { decoded = try CerebralHelmSpotifyCreatePlaylistInput(data: input) } catch {
            throw ToolHandlerError.invalidInput("spotify.createplaylist input does not match its contract.")
        }
        do {
            let result = try await capability.createPlaylist(
                name: decoded.playlistName,
                description: decoded.playlistDescription,
                // Absent means private. Spotify's API defaults this to true, and silently
                // publishing to someone's profile is not a default worth inheriting.
                isPublic: decoded.playlistIsPublic ?? false
            )
            return try CerebralHelmSpotifyCreatePlaylistOutput(
                playlistID: result.id,
                playlistName: result.name,
                playlistURL: result.url
            ).jsonData()
        } catch let error as NativeCapabilityError {
            throw toolHandlerError(from: error)
        }
    }
}

// MARK: - linear.createissue

public struct LinearCreateIssueHandler: ToolHandler {
    public let toolID = "linear.createissue"
    private let capability: any LinearIssueCapability

    public init(capability: any LinearIssueCapability) { self.capability = capability }

    public func execute(input: Data) async throws -> Data {
        let decoded: CerebralHelmLinearCreateIssueInput
        do { decoded = try CerebralHelmLinearCreateIssueInput(data: input) } catch {
            throw ToolHandlerError.invalidInput("linear.createissue input does not match its contract.")
        }
        do {
            let result = try await capability.createIssue(
                title: decoded.issueTitle,
                description: decoded.issueDescription,
                teamID: decoded.linearTeamID,
                projectID: decoded.linearProjectID,
                labelIDs: decoded.linearLabelIDs ?? [],
                priority: decoded.issuePriority
            )
            return try CerebralHelmLinearCreateIssueOutput(
                issueIdentifier: result.identifier,
                issueURL: result.url
            ).jsonData()
        } catch let error as NativeCapabilityError {
            throw toolHandlerError(from: error)
        }
    }
}

// MARK: - project.scaffold

public struct ProjectScaffoldHandler: ToolHandler {
    public let toolID = "project.scaffold"
    private let capability: any ProjectScaffoldCapability

    public init(capability: any ProjectScaffoldCapability) { self.capability = capability }

    public func execute(input: Data) async throws -> Data {
        let decoded: CerebralHelmProjectScaffoldInput
        do { decoded = try CerebralHelmProjectScaffoldInput(data: input) } catch {
            throw ToolHandlerError.invalidInput("project.scaffold input does not match its contract.")
        }
        do {
            let result = try await capability.scaffold(
                name: decoded.projectName,
                location: decoded.projectLocation,
                summary: decoded.projectSummary,
                importance: decoded.projectImportance
            )
            return try CerebralHelmProjectScaffoldOutput(
                projectDescriptorPath: result.descriptorPath,
                projectPath: result.projectPath
            ).jsonData()
        } catch let error as NativeCapabilityError {
            throw toolHandlerError(from: error)
        }
    }
}

// MARK: - git.clone

public struct GitCloneHandler: ToolHandler {
    public let toolID = "git.clone"
    private let capability: any GitCloneCapability

    public init(capability: any GitCloneCapability) { self.capability = capability }

    public func execute(input: Data) async throws -> Data {
        let decoded: CerebralHelmGitCloneInput
        do { decoded = try CerebralHelmGitCloneInput(data: input) } catch {
            throw ToolHandlerError.invalidInput("git.clone input does not match its contract.")
        }
        do {
            let result = try await capability.clone(
                repositoryURL: decoded.repositoryURL,
                directory: decoded.cloneDirectory
            )
            return try CerebralHelmGitCloneOutput(
                clonedPath: result.clonedPath,
                clonedRepositoryName: result.repositoryName
            ).jsonData()
        } catch let error as NativeCapabilityError {
            throw toolHandlerError(from: error)
        }
    }
}

// MARK: - youtube.search

public struct YouTubeSearchHandler: ToolHandler {
    public let toolID = "youtube.search"
    private let capability: any YouTubeSearchCapability

    public init(capability: any YouTubeSearchCapability) { self.capability = capability }

    public func execute(input: Data) async throws -> Data {
        let decoded: CerebralHelmYouTubeSearchInput
        do { decoded = try CerebralHelmYouTubeSearchInput(data: input) } catch {
            throw ToolHandlerError.invalidInput("youtube.search input does not match its contract.")
        }
        do {
            let result = try await capability.search(query: decoded.youtubeQuery)
            return try CerebralHelmYouTubeSearchOutput(
                youtubeOpened: result.opened,
                youtubeQuery: result.query,
                youtubeResolvedURL: result.resolvedURL
            ).jsonData()
        } catch let error as NativeCapabilityError {
            throw toolHandlerError(from: error)
        }
    }
}

public struct SpotifyControlHandler: ToolHandler {
    public let toolID = "spotify.control"
    private let capability: any SpotifyControlCapability

    public init(capability: any SpotifyControlCapability) { self.capability = capability }

    public func execute(input: Data) async throws -> Data {
        let decoded: CerebralHelmSpotifyControlInput
        do { decoded = try CerebralHelmSpotifyControlInput(data: input) } catch {
            throw ToolHandlerError.invalidInput("spotify.control input does not match its contract.")
        }
        do {
            let result = try await capability.control(action: decoded.action.rawValue)
            return try CerebralHelmSpotifyControlOutput(
                action: SpotifyPlaybackAction(rawValue: result.action) ?? decoded.action,
                activeDevice: result.activeDevice,
                applied: result.applied
            ).jsonData()
        } catch let error as NativeCapabilityError {
            throw toolHandlerError(from: error)
        }
    }
}

// MARK: - web.open

public struct WebOpenHandler: ToolHandler {
    public let toolID = "web.open"
    private let capability: any WebOpenCapability

    public init(capability: any WebOpenCapability) { self.capability = capability }

    public func execute(input: Data) async throws -> Data {
        let decoded: CerebralHelmWebOpenInput
        do { decoded = try CerebralHelmWebOpenInput(data: input) } catch {
            throw ToolHandlerError.invalidInput("web.open input does not match its contract.")
        }
        do {
            let result = try await capability.open(url: decoded.url)
            return try CerebralHelmWebOpenOutput(
                opened: result.opened,
                url: result.url
            ).jsonData()
        } catch let error as NativeCapabilityError {
            throw toolHandlerError(from: error)
        }
    }
}

// MARK: - system.status.read

public struct SystemStatusReadHandler: ToolHandler {
    public let toolID = "system.status.read"
    private let capability: any SystemStatusCapability

    public init(capability: any SystemStatusCapability) { self.capability = capability }

    public func execute(input: Data) async throws -> Data {
        let decoded: CerebralHelmSystemStatusReadInput
        do { decoded = try CerebralHelmSystemStatusReadInput(data: input) } catch {
            throw ToolHandlerError.invalidInput("system.status.read input does not match its contract.")
        }
        let ids = (decoded.metrics ?? []).compactMap { SystemMetricID(rawValue: $0.rawValue) }
        do {
            let readings = try await capability.readMetrics(ids)
            let metrics = readings.map { reading in
                Metric(
                    availability: AvailabilityEnum(rawValue: reading.availability.rawValue) ?? .unavailable,
                    id: ID(rawValue: reading.id.rawValue) ?? .cpu,
                    sampledAt: nil,
                    unit: reading.unit,
                    value: reading.value
                )
            }
            return try CerebralHelmSystemStatusReadOutput(metrics: metrics).jsonData()
        } catch let error as NativeCapabilityError {
            throw toolHandlerError(from: error)
        }
    }
}

// MARK: - network.speed.test

public struct NetworkSpeedTestHandler: ToolHandler {
    public let toolID = "network.speed.test"
    private let capability: any NetworkSpeedTestCapability
    private let now: @Sendable () -> Date

    public init(capability: any NetworkSpeedTestCapability, now: @escaping @Sendable () -> Date = { Date() }) {
        self.capability = capability
        self.now = now
    }

    public func execute(input: Data) async throws -> Data {
        do { _ = try CerebralHelmNetworkSpeedTestInput(data: input) } catch {
            throw ToolHandlerError.invalidInput("network.speed.test input does not match its contract.")
        }
        do {
            let reading = try await capability.measure()
            let status: CerebralHelmNetworkSpeedTestOutputStatus
            switch reading.status {
            case .ok: status = .ok
            case .partial: status = .partial
            case .unavailable: status = .unavailable
            }
            let formatter = ISO8601DateFormatter()
            return try CerebralHelmNetworkSpeedTestOutput(
                downloadMbps: reading.downloadMbps,
                status: status,
                testedAt: formatter.string(from: now()),
                uploadMbps: reading.uploadMbps
            ).jsonData()
        } catch let error as NativeCapabilityError {
            throw toolHandlerError(from: error)
        }
    }
}

// MARK: - apps.list

public struct AppsListHandler: ToolHandler {
    public let toolID = "apps.list"
    private let capability: any AppDiscoveryCapability

    public init(capability: any AppDiscoveryCapability) { self.capability = capability }

    public func execute(input: Data) async throws -> Data {
        let decoded: CerebralHelmAppsListInput
        do { decoded = try CerebralHelmAppsListInput(data: input) } catch {
            throw ToolHandlerError.invalidInput("apps.list input does not match its contract.")
        }
        do {
            let result = try await capability.listApplications(includeIcons: decoded.includeIcons ?? true)
            let apps = result.apps.map { app in
                App(bundleID: app.bundleID, iconPNG: app.iconPNGBase64, name: app.name)
            }
            return try CerebralHelmAppsListOutput(apps: apps, truncated: result.truncated).jsonData()
        } catch let error as NativeCapabilityError {
            throw toolHandlerError(from: error)
        }
    }
}

// MARK: - calendar.createevent

/// Creates one event in the user's calendar — the tool behind the `create-event` Input.
///
/// Its `external_write` risk is honest (the event syncs to whatever accounts back that calendar),
/// but its descriptor opts into the user-authored exemption: a person who filled in the form and
/// pressed Create has already authored and reviewed exactly what will happen, so a second
/// confirmation would restate what they just typed. The same call proposed by an agent still
/// confirms, with the values it chose disclosed.
public struct CalendarCreateEventHandler: ToolHandler {
    public let toolID = "calendar.createevent"
    private let capability: any CalendarWritingCapability

    public init(capability: any CalendarWritingCapability) { self.capability = capability }

    public func execute(input: Data) async throws -> Data {
        guard let decoded = try? CerebralHelmCalendarCreateEventInput(data: input) else {
            throw ToolHandlerError.invalidInput("calendar.createevent input does not match its contract.")
        }
        // The schema already constrains the shape; this is the one rule it cannot express, and
        // silently swapping the two would create an event the user did not describe.
        guard decoded.startsAt <= decoded.endsAt else {
            throw ToolHandlerError.invalidInput("calendar.createevent requires endsAt to be at or after startsAt.")
        }
        do {
            let created = try await capability.createEvent(
                title: decoded.title,
                startsAt: decoded.startsAt,
                endsAt: decoded.endsAt,
                calendarID: decoded.calendarID,
                location: decoded.location,
                notes: decoded.notes
            )
            return try CerebralHelmCalendarCreateEventOutput(
                calendarTitle: created.calendarTitle, eventID: created.eventID
            ).jsonData()
        } catch let error as NativeCapabilityError {
            throw toolHandlerError(from: error)
        }
    }
}

// MARK: - app.quit

/// Quits CerebralHelm itself — the action behind the Executive `shut-down` slot and the
/// Settings quit button.
///
/// It takes no target, so it is structurally incapable of quitting anything else; quitting
/// *other* apps is `apps.quitall`, which in turn always excludes the host. Keeping the two
/// apart means neither can be reached through the other.
///
/// The output reports `quitting`, not `quit`: termination has been requested and the
/// process is on its way out, so claiming a completed quit would be asserting something
/// nothing can observe.
public struct AppQuitHandler: ToolHandler {
    public let toolID = "app.quit"
    private let capability: any ApplicationLifecycleCapability

    public init(capability: any ApplicationLifecycleCapability) { self.capability = capability }

    public func execute(input: Data) async throws -> Data {
        do { _ = try CerebralHelmAppQuitInput(data: input) } catch {
            throw ToolHandlerError.invalidInput("app.quit input does not match its contract.")
        }
        do {
            try await capability.quitHostApplication()
            return try CerebralHelmAppQuitOutput(status: .quitting).jsonData()
        } catch let error as NativeCapabilityError {
            throw toolHandlerError(from: error)
        }
    }
}

// MARK: - apps.quitall

/// Quits every regular running application across all modes (NIC-143), excluding the
/// host — a destructive, confirmation-gated bulk action. The target list is discovered
/// at execution time (after the user approves the disclosure), then each app is asked to
/// quit gracefully. An empty desktop yields `status: none` with no ids.
public struct AppsQuitAllHandler: ToolHandler {
    public let toolID = "apps.quitall"
    private let capability: any ApplicationLifecycleCapability

    public init(capability: any ApplicationLifecycleCapability) { self.capability = capability }

    public func execute(input: Data) async throws -> Data {
        do { _ = try CerebralHelmAppsQuitAllInput(data: input) } catch {
            throw ToolHandlerError.invalidInput("apps.quitall input does not match its contract.")
        }
        do {
            let running = try await capability.regularRunningApplicationBundleIDs()
            guard !running.isEmpty else {
                return try CerebralHelmAppsQuitAllOutput(bundleIDS: [], status: .none).jsonData()
            }
            let quit = try await capability.quitApplications(bundleIDs: running)
            return try CerebralHelmAppsQuitAllOutput(
                bundleIDS: quit, status: quit.isEmpty ? .none : .quit
            ).jsonData()
        } catch let error as NativeCapabilityError {
            throw toolHandlerError(from: error)
        }
    }
}

// MARK: - note.capture

public struct NoteCaptureHandler: ToolHandler {
    public let toolID = "note.capture"
    private let knowledge: any KnowledgeService

    public init(knowledge: any KnowledgeService) { self.knowledge = knowledge }

    public func execute(input: Data) async throws -> Data {
        let decoded: CerebralHelmNoteCaptureInput
        do { decoded = try CerebralHelmNoteCaptureInput(data: input) } catch {
            throw ToolHandlerError.invalidInput("note.capture input does not match its contract.")
        }
        let request = NoteCaptureRequest(
            title: decoded.title,
            body: decoded.body,
            kind: decoded.kind,
            project: decoded.project,
            sensitivity: decoded.sensitivity?.rawValue
        )
        do {
            let outcome = try await knowledge.capture(request)
            return try CerebralHelmNoteCaptureOutput(
                created: outcome.created,
                noteID: outcome.noteID,
                path: outcome.path
            ).jsonData()
        } catch let error as KnowledgeServiceError {
            throw toolHandlerError(from: error)
        }
    }
}

// MARK: - note.search

public struct NoteSearchHandler: ToolHandler {
    public let toolID = "note.search"
    private let knowledge: any KnowledgeService

    public init(knowledge: any KnowledgeService) { self.knowledge = knowledge }

    public func execute(input: Data) async throws -> Data {
        let decoded: CerebralHelmNoteSearchInput
        do { decoded = try CerebralHelmNoteSearchInput(data: input) } catch {
            throw ToolHandlerError.invalidInput("note.search input does not match its contract.")
        }
        do {
            let outcome = try await knowledge.search(NoteSearchRequest(query: decoded.query, limit: decoded.limit))
            let results = outcome.hits.map { hit in
                CerebralContracts.Result(
                    excerpt: hit.excerpt,
                    freshness: hit.freshness.flatMap(Freshness.init(rawValue:)),
                    noteID: hit.noteID,
                    path: hit.path,
                    sensitivity: hit.sensitivity.flatMap(Sensitivity.init(rawValue:)),
                    title: hit.title,
                    updated: hit.updated
                )
            }
            return try CerebralHelmNoteSearchOutput(results: results, truncated: outcome.truncated).jsonData()
        } catch let error as KnowledgeServiceError {
            throw toolHandlerError(from: error)
        }
    }
}

// MARK: - note.list

/// Lists the durable notes under the knowledge root (NIC-162).
///
/// Reads the Markdown files rather than the derived index, so a note authored
/// outside CerebralHelm is listed without waiting for a rebuild. Read-only: the
/// descriptor's `read_only` risk means no confirmation, and its
/// `/notes` redaction keeps the user's note titles and paths — an inventory of
/// what they think about — out of the operational log.
public struct NoteListHandler: ToolHandler {
    public let toolID = "note.list"
    private let knowledge: any KnowledgeService

    public init(knowledge: any KnowledgeService) { self.knowledge = knowledge }

    public func execute(input: Data) async throws -> Data {
        let decoded: CerebralHelmNoteListInput
        do { decoded = try CerebralHelmNoteListInput(data: input) } catch {
            throw ToolHandlerError.invalidInput("note.list input does not match its contract.")
        }
        do {
            let outcome = try await knowledge.list(NoteListRequest(limit: decoded.limit))
            let notes = outcome.entries.map { entry in
                NoteListItem(
                    folder: entry.folder,
                    noteID: entry.noteID,
                    path: entry.path,
                    project: entry.project,
                    sensitivity: entry.sensitivity.flatMap(Sensitivity.init(rawValue:)),
                    title: entry.title,
                    updated: entry.updated
                )
            }
            return try CerebralHelmNoteListOutput(
                notes: notes, root: outcome.root, total: outcome.total, truncated: outcome.truncated
            ).jsonData()
        } catch let error as KnowledgeServiceError {
            throw toolHandlerError(from: error)
        }
    }
}

// MARK: - note.read

/// Reads one note by its root-relative path (NIC-162).
///
/// The contract constrains the path to root-relative Markdown, and the knowledge
/// service resolves it and refuses anything landing outside the knowledge root —
/// so neither a traversal nor a symlink reads a file the root does not contain.
/// The descriptor redacts `/body` and `/frontmatter`, so a note's contents never
/// reach a `tool_calls` row (FR-OBS-03).
public struct NoteReadHandler: ToolHandler {
    public let toolID = "note.read"
    private let knowledge: any KnowledgeService

    public init(knowledge: any KnowledgeService) { self.knowledge = knowledge }

    public func execute(input: Data) async throws -> Data {
        let decoded: CerebralHelmNoteReadInput
        do { decoded = try CerebralHelmNoteReadInput(data: input) } catch {
            throw ToolHandlerError.invalidInput("note.read input does not match its contract.")
        }
        do {
            let note = try await knowledge.read(NoteReadRequest(path: decoded.path))
            return try CerebralHelmNoteReadOutput(
                body: note.body,
                frontmatter: note.frontmatter,
                noteID: note.noteID,
                path: note.path,
                root: note.root,
                title: note.title,
                updated: note.updated
            ).jsonData()
        } catch let error as KnowledgeServiceError {
            throw toolHandlerError(from: error)
        }
    }
}
