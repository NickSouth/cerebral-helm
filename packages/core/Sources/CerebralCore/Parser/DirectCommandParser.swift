import Foundation

/// Deterministic, model-free parser for direct commands.
///
/// Supported grammar (FR-CMD-02):
/// - `open <id>`   — resolve an app or URL reference
/// - `mode <id>`   — apply a configured mode
/// - `note <text>` — capture a note
/// - `search <text>` — search notes
/// - `hook <id>`   — run a configured hook
/// - `run <id>`    — run a configured workflow / quick action
/// - `apps`        — list installed applications (read-only discovery)
///
/// Unknown verbs and unresolved references return suggestions without
/// executing; a token matching more than one catalog returns a reviewable
/// ambiguity error. The parser never invokes a model or guesses an intent.
public struct DirectCommandParser: Sendable {
    public let references: CommandReferences

    /// Human-readable patterns offered when input is empty or the verb is unknown.
    public static let supportedPatterns = [
        "open <app|url>",
        "mode <id>",
        "note <text>",
        "search <text>",
        "hook <id>",
        "run <action>",
        "apps",
    ]

    public init(references: CommandReferences) {
        self.references = references
    }

    public func parse(_ rawInput: String) -> ParseResult {
        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .unrecognized(UnrecognizedInput(reason: .emptyInput, suggestions: Self.supportedPatterns))
        }

        let (verb, remainder) = splitVerb(trimmed)

        switch verb {
        case "open":
            return parseOpen(remainder)
        case "mode":
            return parseMode(remainder)
        case "hook":
            return parseHook(remainder)
        case "run":
            return parseRun(remainder)
        case "note":
            return parseFreeText(verb: "note", remainder: remainder) { .captureNote(text: $0) }
        case "search":
            return parseFreeText(verb: "search", remainder: remainder) { .searchNotes(query: $0) }
        case "apps":
            // Argument-free by design: discovery is all-or-nothing and read-only.
            return .parsed(.listApps)
        default:
            return .unrecognized(UnrecognizedInput(reason: .unknownVerb(verb), suggestions: Self.supportedPatterns))
        }
    }

    // MARK: - Verb handlers

    private func parseOpen(_ remainder: String) -> ParseResult {
        let token = firstToken(remainder)
        guard !token.isEmpty else {
            return .unrecognized(UnrecognizedInput(reason: .missingArgument(verb: "open"), suggestions: openSuggestions()))
        }

        let app = references.apps[token]
        let url = references.urls[token]

        switch (app, url) {
        case let (.some(app), .none):
            return .parsed(.openApp(app))
        case let (.none, .some(url)):
            return .parsed(.openURL(url))
        case let (.some(app), .some(url)):
            return .ambiguous(AmbiguousReference(
                verb: "open",
                token: token,
                candidates: [
                    AmbiguousReference.Candidate(kind: "app", id: app.id),
                    AmbiguousReference.Candidate(kind: "url", id: url.id),
                ]
            ))
        case (.none, .none):
            return .unrecognized(UnrecognizedInput(
                reason: .unresolvedReference(verb: "open", token: token),
                suggestions: openSuggestions()
            ))
        }
    }

    private func parseMode(_ remainder: String) -> ParseResult {
        let token = firstToken(remainder)
        guard !token.isEmpty else {
            return .unrecognized(UnrecognizedInput(reason: .missingArgument(verb: "mode"), suggestions: references.modeIds.sorted()))
        }
        if references.modeIds.contains(token) {
            return .parsed(.applyMode(modeId: token))
        }
        return .unrecognized(UnrecognizedInput(
            reason: .unresolvedReference(verb: "mode", token: token),
            suggestions: references.modeIds.sorted()
        ))
    }

    private func parseHook(_ remainder: String) -> ParseResult {
        let token = firstToken(remainder)
        guard !token.isEmpty else {
            return .unrecognized(UnrecognizedInput(reason: .missingArgument(verb: "hook"), suggestions: references.hooks.keys.sorted()))
        }
        if let hook = references.hooks[token] {
            return .parsed(.runHook(hook))
        }
        return .unrecognized(UnrecognizedInput(
            reason: .unresolvedReference(verb: "hook", token: token),
            suggestions: references.hooks.keys.sorted()
        ))
    }

    private func parseRun(_ remainder: String) -> ParseResult {
        let token = firstToken(remainder)
        guard !token.isEmpty else {
            return .unrecognized(UnrecognizedInput(reason: .missingArgument(verb: "run"), suggestions: references.workflowIds.sorted()))
        }
        if references.workflowIds.contains(token) {
            return .parsed(.runAction(actionId: token))
        }
        return .unrecognized(UnrecognizedInput(
            reason: .unresolvedReference(verb: "run", token: token),
            suggestions: references.workflowIds.sorted()
        ))
    }

    private func parseFreeText(
        verb: String,
        remainder: String,
        intent: (String) -> CommandIntent
    ) -> ParseResult {
        guard !remainder.isEmpty else {
            return .unrecognized(UnrecognizedInput(reason: .missingArgument(verb: verb), suggestions: Self.supportedPatterns))
        }
        return .parsed(intent(remainder))
    }

    // MARK: - Helpers

    private func openSuggestions() -> [String] {
        (Array(references.apps.keys) + Array(references.urls.keys)).sorted()
    }

    private func splitVerb(_ input: String) -> (verb: String, remainder: String) {
        guard let range = input.rangeOfCharacter(from: .whitespaces) else {
            return (input.lowercased(), "")
        }
        let verb = String(input[..<range.lowerBound]).lowercased()
        let remainder = String(input[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        return (verb, remainder)
    }

    private func firstToken(_ input: String) -> String {
        input.split(whereSeparator: { $0 == " " || $0 == "\t" }).first.map(String.init) ?? ""
    }
}
