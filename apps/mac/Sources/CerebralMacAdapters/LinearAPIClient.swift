// Linear GraphQL API client (quick-actions phase 4) — the `create-ticket` action's provider.
#if canImport(AppKit)
import Foundation
import CerebralCore
import CerebralTools

/// One issue-tracker workspace as the `create-ticket` form needs it: the teams the key can see,
/// each with its own projects and labels.
///
/// The projects and labels are nested **inside** their team rather than flattened, because they are
/// scoped to it: a flat list would let the form offer a project that belongs to a different team,
/// which Linear rejects at write time. Nesting makes that impossible to express.
public struct LinearWorkspace: Equatable, Sendable {
    public struct NamedOption: Equatable, Sendable {
        public let id: String
        public let name: String
        public init(id: String, name: String) {
            self.id = id
            self.name = name
        }
    }

    public struct Team: Equatable, Sendable {
        public let id: String
        public let key: String
        public let name: String
        public let projects: [NamedOption]
        public let labels: [NamedOption]

        public init(id: String, key: String, name: String, projects: [NamedOption], labels: [NamedOption]) {
            self.id = id
            self.key = key
            self.name = name
            self.projects = projects
            self.labels = labels
        }
    }

    public let teams: [Team]
    public init(teams: [Team]) {
        self.teams = teams
    }
}

/// Reading the workspace is a **separate port** from writing an issue (``LinearIssueCapability``),
/// the same split as `CalendarProvider` versus `CalendarWritingCapability`: the form's dropdowns
/// must not reach the path that files a ticket.
public protocol LinearWorkspaceProviding: Sendable {
    func workspace() async throws -> LinearWorkspace
}

/// Errors this client raises, kept distinct so each degrades honestly rather than as one opaque
/// failure. `credentialsMissing` is the common first-run case and deserves its own message.
public enum LinearAPIError: Error, Equatable, Sendable {
    case credentialsMissing
    case unauthorized
    case rateLimited
    case providerFailed(String)
}

/// Talks to Linear's GraphQL API at `https://api.linear.app/graphql`.
///
/// **Verified live against the real API on 2026-08-03**, not inferred: the endpoint, the header
/// format (`Authorization: <key>` with **no** `Bearer` prefix, which is the OAuth form and would
/// fail here), the `issueCreate(input:)` mutation and its `IssueCreateInput` field names, and the
/// `identifier`/`url` fields on `Issue`.
///
/// The key is read from the Keychain per call rather than captured at construction, so re-pasting a
/// key in Settings takes effect immediately instead of on next launch — the same reason
/// `SpotifyAuthSession` was refactored to read its Client ID at refresh time.
///
/// GraphQL always answers `200`, so a request that "succeeded" can still carry an `errors` array;
/// this treats a populated `errors` as a failure, because a caller reading only the HTTP status
/// would otherwise report a ticket that was never filed.
public struct LinearAPIClient: LinearIssueCapability, LinearWorkspaceProviding {
    public static let secretReference = "linear_api_token"

    private let session: URLSession
    private let endpoint: URL
    private let secretStore: any SecretStoreManaging

    public init(
        secretStore: any SecretStoreManaging,
        session: URLSession? = nil,
        endpoint: URL = URL(string: "https://api.linear.app/graphql")!,
        resourceTimeout: TimeInterval = 20
    ) {
        self.secretStore = secretStore
        self.endpoint = endpoint
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForResource = resourceTimeout
            config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            self.session = URLSession(configuration: config)
        }
    }

    // MARK: - LinearIssueCapability (write)

    public func createIssue(
        title: String,
        description: String?,
        teamID: String,
        projectID: String?,
        labelIDs: [String],
        priority: Int?
    ) async throws -> LinearIssueResult {
        // Values travel as GraphQL **variables**, never interpolated into the query string: a title
        // containing a quote or a brace is then data, not syntax, and cannot alter the mutation.
        var input: [String: Any] = ["title": title, "teamId": teamID]
        if let description, !description.isEmpty { input["description"] = description }
        if let projectID, !projectID.isEmpty { input["projectId"] = projectID }
        // Omitted entirely rather than sent empty: `labelIds: []` reads as "clear the labels",
        // which is a different instruction from "do not set any".
        let labels = labelIDs.filter { !$0.isEmpty }
        if !labels.isEmpty { input["labelIds"] = labels }
        if let priority { input["priority"] = priority }

        // The tool boundary speaks `NativeCapabilityError`, so the typed API errors are translated
        // here rather than leaking a Linear-shaped error into the executor's classification.
        let payload: [String: Any]
        do {
            payload = try await send(query: Self.createIssueMutation, variables: ["input": input])
        } catch let error as LinearAPIError {
            throw Self.capabilityError(from: error)
        }

        guard
            let issueCreate = payload["issueCreate"] as? [String: Any],
            issueCreate["success"] as? Bool == true,
            let issue = issueCreate["issue"] as? [String: Any],
            let identifier = issue["identifier"] as? String,
            let url = issue["url"] as? String
        else {
            throw NativeCapabilityError.adapterFailure("Linear did not confirm the issue was created.")
        }
        return LinearIssueResult(identifier: identifier, url: url)
    }

    // MARK: - LinearWorkspaceProviding (read)

    public func workspace() async throws -> LinearWorkspace {
        let payload = try await send(query: Self.workspaceQuery, variables: [:])
        guard
            let teams = payload["teams"] as? [String: Any],
            let nodes = teams["nodes"] as? [[String: Any]]
        else {
            throw LinearAPIError.providerFailed("Linear returned no teams.")
        }
        return LinearWorkspace(teams: nodes.compactMap(Self.decodeTeam))
    }

    // MARK: - Transport

    private func apiKey() async throws -> String {
        let stored: String
        do {
            stored = try await secretStore.readValue(reference: Self.secretReference)
        } catch {
            throw LinearAPIError.credentialsMissing
        }
        let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LinearAPIError.credentialsMissing }
        return trimmed
    }

    /// Sends one GraphQL document and returns its `data` object, translating every failure mode
    /// into a typed error. The key goes in the header, never the URL or the body, so it cannot
    /// reach a log through a request description (FR-OBS-03).
    private func send(query: String, variables: [String: Any]) async throws -> [String: Any] {
        let key = try await apiKey()

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // No `Bearer` prefix: that is the OAuth form. A personal API key is sent raw (verified).
        request.setValue(key, forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: ["query": query, "variables": variables]
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw NativeCapabilityError.cancelled
        } catch {
            throw LinearAPIError.providerFailed(error.localizedDescription)
        }

        if let http = response as? HTTPURLResponse {
            switch http.statusCode {
            case 200...299: break
            case 401, 403: throw LinearAPIError.unauthorized
            case 429: throw LinearAPIError.rateLimited
            default: throw LinearAPIError.providerFailed("Linear returned HTTP \(http.statusCode).")
            }
        }

        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LinearAPIError.providerFailed("Linear returned a response that could not be read.")
        }
        // GraphQL answers 200 even when the operation failed, so `errors` is the real status.
        if let errors = root["errors"] as? [[String: Any]], !errors.isEmpty {
            throw LinearAPIError.providerFailed(Self.message(from: errors))
        }
        guard let payload = root["data"] as? [String: Any] else {
            throw LinearAPIError.providerFailed("Linear returned no data.")
        }
        return payload
    }

    // MARK: - Pure helpers (unit-tested)

    static let createIssueMutation = """
    mutation CerebralHelmIssueCreate($input: IssueCreateInput!) {
      issueCreate(input: $input) {
        success
        issue { id identifier url title }
      }
    }
    """

    static let workspaceQuery = """
    query CerebralHelmWorkspace {
      teams(first: 50) {
        nodes {
          id
          key
          name
          projects(first: 50) { nodes { id name } }
          labels(first: 100) { nodes { id name } }
        }
      }
    }
    """

    /// Reports Linear's own first message. A partially-shaped team is dropped rather than rendered
    /// with blanks, so a dropdown never offers an option that cannot be filed against.
    static func decodeTeam(_ node: [String: Any]) -> LinearWorkspace.Team? {
        guard
            let id = node["id"] as? String,
            let key = node["key"] as? String,
            let name = node["name"] as? String
        else { return nil }
        return LinearWorkspace.Team(
            id: id,
            key: key,
            name: name,
            projects: options(in: node["projects"]),
            labels: options(in: node["labels"])
        )
    }

    static func options(in container: Any?) -> [LinearWorkspace.NamedOption] {
        guard
            let container = container as? [String: Any],
            let nodes = container["nodes"] as? [[String: Any]]
        else { return [] }
        return nodes.compactMap { node in
            guard let id = node["id"] as? String, let name = node["name"] as? String else { return nil }
            return LinearWorkspace.NamedOption(id: id, name: name)
        }
    }

    /// Maps a Linear failure onto the tool boundary's error type. A missing key is `notFound` with
    /// the remedy in the message rather than a bare "unavailable", because it is the first-run
    /// case and the user can fix it in one step.
    static func capabilityError(from error: LinearAPIError) -> NativeCapabilityError {
        switch error {
        case .credentialsMissing:
            return .notFound("No Linear API key is stored. Add one under Settings → Setup.")
        case .unauthorized:
            return .permissionDenied
        case .rateLimited:
            return .adapterFailure("Linear's rate limit was reached. Try again shortly.")
        case let .providerFailed(message):
            return .adapterFailure(message)
        }
    }

    static func message(from errors: [[String: Any]]) -> String {
        let first = errors.first?["message"] as? String
        return first.map { "Linear refused the request: \($0)" } ?? "Linear refused the request."
    }
}
#endif
