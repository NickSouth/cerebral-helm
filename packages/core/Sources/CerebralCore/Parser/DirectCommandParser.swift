import Foundation

/// Deterministic, model-free parser for direct commands.
///
/// Supported grammar (FR-CMD-02):
/// - `open <id>`   — resolve an app or URL reference
/// - `mode <id>`   — apply a configured mode
/// - `note <text>` — capture a note
/// - `project <path>` — open a repository directory in the configured editor
/// - `search <text>` — search notes
/// - `notes-list [n]` — list the notes under the knowledge root (read-only)
/// - `notes-read <path>` — read one note by its root-relative path (read-only)
/// - `hook <id>`   — run a configured hook
/// - `run <id>`    — run a configured workflow / quick action
/// - `apps`        — list installed applications (read-only discovery)
///
/// The note-read verbs are hyphenated (like `quit-all`) rather than the shorter
/// `notes` / `read`, because `notes` is already the Notes **app** reference id —
/// a bare `notes` verb would hijack `open notes` for anyone with that app
/// configured. A verb must not shadow a reference the user already owns.
///
/// They are also addressable but **not** advertised in ``supportedPatterns`` or
/// the suggestion engine's verb catalog (NIC-162): they return data to a caller —
/// the settings Library surface, the CLI, and eventually an assistant — and
/// typing one into the palette would show the user nothing. Offering a command
/// with no visible result is exactly the dishonesty the placeholder rules exist
/// to prevent, so they stay unlisted until a surface renders them.
///
/// Unknown verbs and unresolved references return suggestions without
/// executing; a token matching more than one catalog returns a reviewable
/// ambiguity error. The parser never invokes a model or guesses an intent.
public struct DirectCommandParser: Sendable {
    private let referenceStore: CommandReferenceStore

    /// The live reference catalog. Reads the current snapshot on each access, so a
    /// reference minted mid-session (NIC-146) resolves through `open <id>` without a
    /// relaunch.
    public var references: CommandReferences { referenceStore.current }

    /// Human-readable patterns offered when input is empty or the verb is unknown.
    public static let supportedPatterns = [
        "open <app|url>",
        "mode <id>",
        "note <text>",
        "project <path>",
        "search <text>",
        "google <query>",
        "youtube <query>",
        "clone <url>",
        "spotify <action>",
        "web <url>",
        "hook <id>",
        "run <action>",
        "apps",
        "speedtest",
        "quit-all",
    ]

    public init(references: CommandReferences) {
        self.referenceStore = CommandReferenceStore(references)
    }

    /// Composes the parser over a shared, reloadable catalog store (NIC-146) so a
    /// mid-session mint reaches `open <id>` resolution live.
    public init(referenceStore: CommandReferenceStore) {
        self.referenceStore = referenceStore
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
        case "project":
            // The remainder is the whole repository path (paths may contain spaces),
            // so the free-text handler takes it verbatim (NIC-131).
            return parseFreeText(verb: "project", remainder: remainder) { .openProject(repoPath: $0) }
        case "search":
            return parseFreeText(verb: "search", remainder: remainder) { .searchNotes(query: $0) }
        case "notes-list":
            return parseNotesList(remainder)
        case "notes-read":
            // The remainder is the whole root-relative path (note paths contain
            // spaces — a file authored elsewhere is titled by its filename), so the
            // free-text handler takes it verbatim. One hyphenated verb rather than
            // `note read <path>`: `note <text>` is capture, and would swallow it.
            return parseFreeText(verb: "notes-read", remainder: remainder) { .readNote(path: $0) }
        case "google":
            // The remainder is the whole search query (queries contain spaces), taken verbatim
            // (NIC-134). The adapter builds the google.com search URL; only this query varies.
            return parseFreeText(verb: "google", remainder: remainder) { .googleSearch(query: $0) }
        case "youtube":
            // Same shape as `google`: the remainder is the whole query, taken verbatim. A separate
            // verb rather than `google site:youtube.com` because the adapter — not the caller —
            // owns the destination host, which is the property that makes the query pure data.
            return parseFreeText(verb: "youtube", remainder: remainder) { .youtubeSearch(query: $0) }
        case "clone":
            // The remainder is the repository URL. The typed grammar carries no destination — the
            // adapter derives the folder from the repository name and keeps it inside the projects
            // root — so a clone typed into the palette can never choose where it lands.
            return parseFreeText(verb: "clone", remainder: remainder) { .cloneRepository(url: $0, directory: nil) }
        case "spotify":
            // The remainder is the playback action (play/pause/next/previous), taken verbatim
            // (NIC-133). The tool descriptor validates it against the input enum; an unknown action
            // is refused by the contract, not acted on.
            return parseFreeText(verb: "spotify", remainder: remainder) { .spotifyControl(action: $0) }
        case "web":
            // The remainder is the whole https URL, taken verbatim (NIC-127). The adapter
            // validates the scheme/host; a non-https or malformed link is refused, not opened.
            return parseFreeText(verb: "web", remainder: remainder) { .webOpen(url: $0) }
        case "apps":
            // Argument-free by design: discovery is all-or-nothing and read-only.
            return .parsed(.listApps)
        case "speedtest":
            // Argument-free by design: one on-demand internet capacity read (NIC-135).
            return .parsed(.runSpeedTest)
        case "quit-all":
            // Argument-free by design: quit every open app across all modes (NIC-143).
            // Destructive — the command bus gates it on a confirmation.
            return .parsed(.quitAllApps)
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

    /// `notes-list [n]` — the whole library, or its `n` most recently changed
    /// notes. The cap is part of the grammar so every caller can ask for one: a
    /// tool input no command can set would be a contract nothing honors.
    private func parseNotesList(_ remainder: String) -> ParseResult {
        let token = firstToken(remainder)
        guard !token.isEmpty else { return .parsed(.listNotes(limit: nil)) }
        guard let limit = Int(token), limit > 0 else {
            // Not a cap, and not something to guess at — a listing that silently
            // ignored its argument would misreport what it returned.
            return .unrecognized(UnrecognizedInput(
                reason: .unresolvedReference(verb: "notes-list", token: token),
                suggestions: ["notes-list", "notes-list 50"]
            ))
        }
        return .parsed(.listNotes(limit: limit))
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
