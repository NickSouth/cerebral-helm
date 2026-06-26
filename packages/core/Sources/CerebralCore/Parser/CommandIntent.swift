/// A typed, model-free intent produced by the direct-command parser.
///
/// Intents describe *what* was requested; mapping them onto command-envelope
/// payloads and execution belongs to the bus and CLI (NIC-25, NIC-26).
public enum CommandIntent: Equatable, Sendable {
    case openApp(ReferenceEntry)
    case openURL(ReferenceEntry)
    case applyMode(modeId: String)
    case captureNote(text: String)
    case searchNotes(query: String)
    case runHook(ReferenceEntry)
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
