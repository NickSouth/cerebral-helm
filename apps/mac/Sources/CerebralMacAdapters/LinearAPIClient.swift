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

/// One project's position in the **currently-active cycle** (NIC-221): the cycle itself, and the
/// issues of that project which sit in it.
///
/// Shapes verified against Linear's generated schema (`@linear/sdk` 90.0.0, read 2026-08-20), not
/// inferred: `IssueFilter.project` is a `NullableProjectFilter` carrying a `StringComparator`,
/// `IssueFilter.cycle` is a `NullableCycleFilter` carrying `isActive: BooleanComparator`, and
/// every selected field exists on `Issue`/`WorkflowState`/`Cycle` with the spelling used here.
public struct LinearProjectCycle: Equatable, Sendable {
    /// A workflow state as Linear defines it. `type` is the only stable thing to group on — it is
    /// one of `backlog`, `unstarted`, `started`, `completed`, `canceled`, and unlike `name` it
    /// survives the user renaming a status. `color` is Linear's own, so the surface never invents
    /// a palette for statuses it does not own; `position` orders states within a type.
    public struct State: Equatable, Sendable {
        public let name: String
        public let type: String
        public let color: String
        public let position: Double

        public init(name: String, type: String, color: String, position: Double) {
            self.name = name
            self.type = type
            self.color = color
            self.position = position
        }
    }

    /// One issue as the cycle list renders it. Deliberately **no description**: the surface shows
    /// titles, and the less of an issue's prose crosses the bridge the better.
    public struct Issue: Equatable, Sendable {
        public let identifier: String
        public let title: String
        /// Linear's own issue URL — the row opens this rather than composing one from the id.
        public let url: String
        /// Linear's scale: 0 none, 1 urgent, 2 high, 3 medium, 4 low.
        public let priority: Int
        public let estimate: Int?
        public let sortOrder: Double
        public let state: State
        public let labels: [String]
        /// The assignee's display name, or `nil` when unassigned. Verified live 2026-08-20: this
        /// is Linear's **handle** (`nickrsouthey`), not a person's name — it labels the row for
        /// assistive tech, while ``assigneeInitials`` is what an avatar should draw.
        public let assignee: String?
        /// Linear's own initials for the assignee (`NS`), or `nil` when unassigned. Taken from the
        /// API rather than derived from the handle, which would render "n".
        public let assigneeInitials: String?

        public init(
            identifier: String,
            title: String,
            url: String,
            priority: Int,
            estimate: Int?,
            sortOrder: Double,
            state: State,
            labels: [String],
            assignee: String?,
            assigneeInitials: String?
        ) {
            self.identifier = identifier
            self.title = title
            self.url = url
            self.priority = priority
            self.estimate = estimate
            self.sortOrder = sortOrder
            self.state = state
            self.labels = labels
            self.assignee = assignee
            self.assigneeInitials = assigneeInitials
        }
    }

    public struct Cycle: Equatable, Sendable {
        public let id: String
        public let number: Int
        /// Cycles are usually unnamed; the surface falls back to "Cycle <number>".
        public let name: String?
        public let startsAt: Date
        public let endsAt: Date

        public init(id: String, number: Int, name: String?, startsAt: Date, endsAt: Date) {
            self.id = id
            self.number = number
            self.name = name
            self.startsAt = startsAt
            self.endsAt = endsAt
        }
    }

    /// The project's name as **Linear** spells it, or `nil` when no project matches the descriptor's
    /// `linear_project` at all.
    ///
    /// This exists because of a live finding (2026-08-20): a misspelled project name returns zero
    /// issues, which is byte-identical to a correctly-linked project that simply has nothing in the
    /// cycle. Without this the surface would quietly render a typo as "nothing to do" — the worst
    /// kind of wrong, because it looks like an answer. It also lets the header echo the canonical
    /// casing back, confirming which project was matched.
    public let matchedProject: String?
    /// The active cycle, or `nil` when there is none running — between cycles is a real state and
    /// reads differently from "a cycle is running and this project has nothing in it".
    public let cycle: Cycle?
    public let issues: [Issue]
    /// True when Linear had more issues than one page returned. Surfaced rather than swallowed: a
    /// list silently cut at the page size reads as complete when it is not.
    public let truncated: Bool

    public init(matchedProject: String?, cycle: Cycle?, issues: [Issue], truncated: Bool) {
        self.matchedProject = matchedProject
        self.cycle = cycle
        self.issues = issues
        self.truncated = truncated
    }
}

/// Reads one project's active-cycle issues (NIC-221). A **third** port, separate again from both
/// ``LinearWorkspaceProviding`` and the write capability: a surface that renders a project's
/// status must not be able to reach the one that files tickets.
public protocol LinearProjectCycleProviding: Sendable {
    /// - Parameter projectName: the Linear project name, matched case-insensitively, as declared
    ///   by a descriptor's `linear_project` frontmatter key.
    func projectCycle(named projectName: String) async throws -> LinearProjectCycle
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
public struct LinearAPIClient: LinearIssueCapability, LinearWorkspaceProviding, LinearProjectCycleProviding {
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

    // MARK: - LinearProjectCycleProviding (read)

    public func projectCycle(named projectName: String) async throws -> LinearProjectCycle {
        let name = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        // A blank name would ask Linear for a project called "" and get an empty answer that reads
        // as "nothing in this cycle". Refused here so the caller cannot mistake one for the other.
        guard !name.isEmpty else {
            throw LinearAPIError.providerFailed("No Linear project name was given.")
        }

        let payload = try await send(query: Self.projectCycleQuery, variables: ["project": name])

        let container = payload["issues"] as? [String: Any]
        let nodes = container?["nodes"] as? [[String: Any]] ?? []
        let issues = nodes.compactMap(Self.decodeIssue)
        let pageInfo = container?["pageInfo"] as? [String: Any]

        return LinearProjectCycle(
            matchedProject: Self.matchedProjectName(in: payload),
            cycle: Self.resolveCycle(issueNodes: nodes, payload: payload),
            issues: issues,
            truncated: pageInfo?["hasNextPage"] as? Bool == true
        )
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

    /// One project's issues in the active cycle, plus the active cycle itself (NIC-221).
    ///
    /// Three root fields in one document rather than three round trips, and each earns its place
    /// by separating a state that would otherwise collapse into another:
    ///
    /// - `projects` distinguishes **"no such project"** from "this project has nothing in the
    ///   cycle" — verified live (2026-08-20) to be the same zero-issue response otherwise, which
    ///   would render a misspelled `linear_project` as "nothing to do".
    /// - `cycles` answers the **empty** case: with no issues there is no issue to read the cycle
    ///   off, and "there is no active cycle" must not collapse into "the cycle is running and this
    ///   project has nothing in it".
    ///
    /// The project is matched with `eqIgnoreCase` because the name is hand-typed into a
    /// `PROJECT.md` frontmatter key, where casing is not something to fail a lookup over.
    ///
    /// `first: 250` is Linear's page ceiling; `pageInfo.hasNextPage` rides along so a truncated
    /// list can say so instead of looking complete.
    static let projectCycleQuery = """
    query CerebralHelmProjectCycle($project: String!) {
      projects(first: 1, filter: { name: { eqIgnoreCase: $project } }) {
        nodes { id name }
      }
      cycles(first: 1, filter: { isActive: { eq: true } }) {
        nodes { id number name startsAt endsAt }
      }
      issues(
        first: 250
        filter: {
          project: { name: { eqIgnoreCase: $project } }
          cycle: { isActive: { eq: true } }
        }
      ) {
        pageInfo { hasNextPage }
        nodes {
          identifier
          title
          url
          priority
          estimate
          sortOrder
          state { name type color position }
          labels(first: 10) { nodes { name } }
          assignee { displayName initials }
          cycle { id number name startsAt endsAt }
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

    // MARK: - Project-cycle decoding (NIC-221)

    /// Decodes one issue node, or `nil` when a field the row cannot render without is missing.
    /// Dropping a partial issue is the same rule the team decoder follows: a row rendered with
    /// blanks claims to be an issue you can act on, and this one would not open.
    static func decodeIssue(_ node: [String: Any]) -> LinearProjectCycle.Issue? {
        guard
            let identifier = node["identifier"] as? String,
            let title = node["title"] as? String,
            let url = node["url"] as? String,
            let stateNode = node["state"] as? [String: Any],
            let state = decodeState(stateNode)
        else { return nil }

        let assignee = node["assignee"] as? [String: Any]
        return LinearProjectCycle.Issue(
            identifier: identifier,
            title: title,
            url: url,
            // Linear types priority and estimate as Float; they are whole numbers in practice, and
            // the surface shows them as such.
            priority: Int(number(node["priority"]) ?? 0),
            estimate: number(node["estimate"]).map(Int.init),
            sortOrder: number(node["sortOrder"]) ?? 0,
            state: state,
            labels: labelNames(in: node["labels"]),
            assignee: assignee?["displayName"] as? String,
            assigneeInitials: assignee?["initials"] as? String
        )
    }

    static func decodeState(_ node: [String: Any]) -> LinearProjectCycle.State? {
        guard
            let name = node["name"] as? String,
            let type = node["type"] as? String,
            let color = node["color"] as? String
        else { return nil }
        return LinearProjectCycle.State(
            name: name, type: type, color: color, position: number(node["position"]) ?? 0
        )
    }

    static func decodeCycle(_ node: [String: Any]) -> LinearProjectCycle.Cycle? {
        guard
            let id = node["id"] as? String,
            let number = number(node["number"]),
            let startsAt = date(node["startsAt"]),
            let endsAt = date(node["endsAt"])
        else { return nil }
        return LinearProjectCycle.Cycle(
            id: id,
            number: Int(number),
            name: node["name"] as? String,
            startsAt: startsAt,
            endsAt: endsAt
        )
    }

    /// The cycle to report: the one the returned issues are actually in, falling back to the
    /// workspace's active cycle when the project has none in it. Preferring the issues' own cycle
    /// means the header can never name a different cycle from the rows beneath it.
    static func resolveCycle(
        issueNodes: [[String: Any]], payload: [String: Any]
    ) -> LinearProjectCycle.Cycle? {
        for node in issueNodes {
            if let cycleNode = node["cycle"] as? [String: Any], let cycle = decodeCycle(cycleNode) {
                return cycle
            }
        }
        guard
            let cycles = payload["cycles"] as? [String: Any],
            let nodes = cycles["nodes"] as? [[String: Any]]
        else { return nil }
        return nodes.compactMap(decodeCycle).first
    }

    /// The matched project's name as Linear spells it, or `nil` when the name matched nothing.
    static func matchedProjectName(in payload: [String: Any]) -> String? {
        guard
            let projects = payload["projects"] as? [String: Any],
            let nodes = projects["nodes"] as? [[String: Any]]
        else { return nil }
        return nodes.compactMap { $0["name"] as? String }.first
    }

    static func labelNames(in container: Any?) -> [String] {
        guard
            let container = container as? [String: Any],
            let nodes = container["nodes"] as? [[String: Any]]
        else { return [] }
        return nodes.compactMap { $0["name"] as? String }
    }

    /// JSON numbers arrive as `NSNumber`, and whether they bridge to `Int` or `Double` depends on
    /// how the value was written — so both are accepted rather than guessed at.
    static func number(_ value: Any?) -> Double? {
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        if let number = value as? NSNumber { return number.doubleValue }
        return nil
    }

    /// Parses one Linear `DateTime`. Built per call rather than held in a `static let`: an
    /// `ISO8601DateFormatter` is a reference type with mutable options, and a shared one inside a
    /// `Sendable` client is a data race waiting for two windows to open at once. A response carries
    /// at most a handful of dates, so the allocation is not worth the risk.
    static func date(_ value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let parsed = withFractional.date(from: text) { return parsed }
        // Linear sends fractional seconds today, but the format is not promised — a plain
        // internet date-time must still parse rather than blanking the cycle header.
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: text)
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
