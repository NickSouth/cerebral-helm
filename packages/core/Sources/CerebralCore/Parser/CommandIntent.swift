/// A typed, model-free intent produced by the direct-command parser.
///
/// Intents describe *what* was requested; mapping them onto command-envelope
/// payloads and execution belongs to the bus and CLI (NIC-25, NIC-26).
public enum CommandIntent: Equatable, Sendable {
    case openApp(ReferenceEntry)
    case openURL(ReferenceEntry)
    case applyMode(modeId: String)
    /// Open a repository directory in the configured editor (NIC-131) — a single
    /// `project.open` tool call. The path is constrained to the projects root by the
    /// adapter, and the `local_write` risk routes it through a confirmation.
    case openProject(repoPath: String)
    case captureNote(text: String)
    case searchNotes(query: String)
    /// Open a Google search for the query in the browser (NIC-134) — a single `google.search`
    /// tool call. The host is fixed to google.com by the adapter; only the query varies.
    case googleSearch(query: String)
    /// Open an https web address in the browser (NIC-127) — a single `web.open` tool call, used
    /// for news article links. The adapter validates the scheme/host; a non-https link is refused.
    case webOpen(url: String)
    case runHook(ReferenceEntry)
    /// Measure current internet download/upload capacity on request (NIC-135) —
    /// a single read-only `network.speed.test` tool call.
    case runSpeedTest
    /// Run a configured workflow / quick action (an ordered plan of tool steps
    /// resolved by the action planner).
    case runAction(actionId: String)
    /// List installed applications, read-only (NIC-119 discovery — feeds the
    /// More Apps picker; never launches anything).
    case listApps
    /// Quit every open regular application across all modes (NIC-143) — a single
    /// destructive, confirmation-gated `apps.quitall` tool call.
    case quitAllApps
}

/// The outcome of parsing one line of direct input.
///
/// Only ``parsed(_:)`` may proceed to execution. ``unrecognized(_:)`` and
/// ``ambiguous(_:)`` both mean "do not execute" — the parser never guesses.
public enum ParseResult: Equatable, Sendable {
    case parsed(CommandIntent)
    case unrecognized(UnrecognizedInput)
    case ambiguous(AmbiguousReference)
}

/// Input that did not resolve to an intent, with suggestions for the user.
public struct UnrecognizedInput: Equatable, Sendable {
    public enum Reason: Equatable, Sendable {
        case emptyInput
        case unknownVerb(String)
        case missingArgument(verb: String)
        case unresolvedReference(verb: String, token: String)
    }

    public let reason: Reason
    public let suggestions: [String]

    public init(reason: Reason, suggestions: [String]) {
        self.reason = reason
        self.suggestions = suggestions
    }
}

/// A reference that matched more than one catalog and is therefore ambiguous —
/// a reviewable error rather than an executed command.
public struct AmbiguousReference: Equatable, Sendable {
    public struct Candidate: Equatable, Sendable {
        /// The catalog the token matched, e.g. `"app"` or `"url"`.
        public let kind: String
        public let id: String

        public init(kind: String, id: String) {
            self.kind = kind
            self.id = id
        }
    }

    public let verb: String
    public let token: String
    public let candidates: [Candidate]

    public init(verb: String, token: String, candidates: [Candidate]) {
        self.verb = verb
        self.token = token
        self.candidates = candidates
    }
}
