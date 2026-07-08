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
                urlID: result.urlID
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
