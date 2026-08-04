import Foundation

/// One ranked candidate the command surfaces can display and execute (NIC-168).
///
/// `command` is always an exact string in the parser's grammar — executing a
/// suggestion means submitting `command` through the normal bus, so the surface
/// resolves fuzzy input while the parser stays exact and never guesses
/// (FR-CMD-02). Template rows (`requiresArgument`) are the exception: their
/// `command` is a fill-in prefix (`"note "`), and the UI completes the input
/// instead of executing.
public struct CommandSuggestion: Equatable, Sendable {
    public enum Kind: String, Sendable {
        case app
        case url
        case workflow
        case mode
        case hook
        /// A directly executable command that is none of the reference kinds —
        /// the as-typed row for free-text verbs (`note …`, `search …`) and the
        /// argument-free verbs (`apps`, `speedtest`, `quit-all`).
        case command
        /// A grammar template offered for discovery; fills the input rather
        /// than executing when it still needs an argument.
        case pattern
    }

    public let command: String
    public let label: String
    /// A short secondary line when the label alone is not self-explanatory
    /// (currently the grammar pattern on template rows).
    public let detail: String?
    public let kind: Kind
    /// True when `command` is an incomplete template — Enter should fill the
    /// input with it, never submit it.
    public let requiresArgument: Bool

    public init(command: String, label: String, detail: String? = nil, kind: Kind, requiresArgument: Bool = false) {
        self.command = command
        self.label = label
        self.detail = detail
        self.kind = kind
        self.requiresArgument = requiresArgument
    }
}

/// Deterministic, model-free suggestion ranking over the live command catalogs
/// (NIC-168).
///
/// Reads the same ``CommandReferenceStore`` the parser resolves against, so a
/// reference minted mid-session is suggestible immediately, plus display labels
/// for modes and workflows (whose catalogs carry only ids). Matching is
/// ``FuzzyMatcher``'s fixed lexical bands; composition is:
///
/// - input that already parses ranks first, exactly as typed, so free-text
///   verbs (`note buy milk`) are never hijacked by a fuzzy reference match;
/// - a known (or typo-close) verb scopes argument completion to that verb's
///   catalog (`open chr` → apps and URLs only);
/// - bare tokens match every catalog by id and label and suggest the full
///   command (`chrme` → `open chrome`, `school` → `mode school`);
/// - verbs themselves match as template rows for discovery, and an empty query
///   lists the supported grammar.
///
/// The engine only ranks. Availability (capability gating) is stamped where the
/// capability map lives, and execution still flows through the command bus and
/// policy engine untouched.
public struct CommandSuggestionEngine: Sendable {
    private let referenceStore: CommandReferenceStore
    private let modeLabels: [String: String]
    private let workflowLabels: [String: String]
    private let parser: DirectCommandParser

    public static let defaultLimit = 8

    public init(
        referenceStore: CommandReferenceStore,
        modeLabels: [String: String] = [:],
        workflowLabels: [String: String] = [:]
    ) {
        self.referenceStore = referenceStore
        self.modeLabels = modeLabels
        self.workflowLabels = workflowLabels
        self.parser = DirectCommandParser(referenceStore: referenceStore)
    }

    /// Suggestions for recently executed direct commands (PRD §9.4 "recent direct
    /// commands"). Each raw input is re-parsed against the LIVE catalog and kept
    /// only when it still resolves to a re-runnable reference or argument-free
    /// intent — a removed reference silently drops out, and free-text intents
    /// (notes, searches, web/google/spotify/project) are excluded so re-running a
    /// capture can never duplicate state and typed text never resurfaces as a
    /// suggestion. Order is preserved (callers pass newest first), deduped.
    public func recentSuggestions(_ rawInputs: [String], limit: Int = 5) -> [CommandSuggestion] {
        guard limit > 0 else { return [] }
        var seen = Set<String>()
        var recents: [CommandSuggestion] = []
        for rawInput in rawInputs {
            guard recents.count < limit else { break }
            let command = Self.collapseWhitespace(rawInput)
            guard
                !command.isEmpty,
                seen.insert(command).inserted,
                case let .parsed(intent) = parser.parse(command),
                Self.isRerunnable(intent)
            else { continue }
            recents.append(asTypedSuggestion(for: intent, command: command))
        }
        return recents
    }

    private static func isRerunnable(_ intent: CommandIntent) -> Bool {
        switch intent {
        case .openApp, .openURL, .applyMode, .runAction, .runHook,
             .listApps, .runSpeedTest, .quitAllApps:
            return true
        // A note read returns data to its caller rather than doing something the
        // user would want repeated from the palette (NIC-162), like a search.
        // `createCalendarEvent` never comes from typed text at all — it is form-submitted, so
        // it can neither appear in the palette nor be re-run from history.
        case .captureNote, .searchNotes, .listNotes, .readNote,
             .googleSearch, .youtubeSearch, .spotifyControl, .webOpen, .openProject, .createCalendarEvent,
             .cloneRepository, .createLinearIssue, .createSpotifyPlaylist, .scaffoldProject, .sendMessage:
            return false
        }
    }

    public func suggest(_ query: String, limit: Int = CommandSuggestionEngine.defaultLimit) -> [CommandSuggestion] {
        guard limit > 0 else { return [] }
        let trimmed = Self.collapseWhitespace(query)
        guard !trimmed.isEmpty else {
            return Verb.all.map { $0.templateSuggestion }.prefix(limit).map { $0 }
        }

        let references = referenceStore.current
        var collector = Collector()

        // Input that already parses executes exactly as typed and always tops the list.
        if case let .parsed(intent) = parser.parse(trimmed) {
            collector.add(asTypedSuggestion(for: intent, command: trimmed), score: 2.0)
        }

        let (firstToken, remainder) = splitFirstToken(trimmed)
        for verb in Verb.all {
            guard let verbScore = FuzzyMatcher.score(query: firstToken, candidate: verb.token) else { continue }
            let exact = firstToken == verb.token
            // A corrected verb keeps the suggestion honest but ranks below what
            // the user actually typed matching something.
            let verbFactor = exact ? 1.0 : 0.8

            if remainder.isEmpty {
                collector.add(verb.templateSuggestion, score: verbScore * 0.95)
                if exact, case let .references(catalog) = verb.argument {
                    // `run` / `mode` / … with no argument yet: offer the whole
                    // catalog, mirroring the parser's missing-argument suggestions.
                    for entry in entries(of: catalog, in: references) {
                        collector.add(entry, score: 0.6)
                    }
                }
                continue
            }

            switch verb.argument {
            case .none:
                continue // Argument-free verbs take no remainder.
            case .freeText:
                guard !exact else { continue } // The as-typed row already covers it.
                collector.add(
                    CommandSuggestion(
                        command: "\(verb.token) \(remainder)",
                        label: verb.description,
                        kind: .command
                    ),
                    score: verbScore * 0.8
                )
            case let .references(catalog):
                for entry in entries(of: catalog, in: references) {
                    guard let argScore = entry.match(remainder) else { continue }
                    collector.add(entry, score: argScore * verbFactor)
                }
            }
        }

        // Bare matching across every catalog: "chrme" → `open chrome`,
        // "google chrome" → `open chrome` by label, "school" → `mode school`.
        for catalog in Verb.Catalog.allCases {
            for entry in entries(of: catalog, in: references) {
                guard let score = entry.match(trimmed) else { continue }
                collector.add(entry, score: score)
            }
        }

        return collector.ranked(limit: limit)
    }

    // MARK: - Catalog entries

    /// A suggestible catalog entry plus the strings it matches on.
    private struct Candidate {
        let suggestion: CommandSuggestion
        let id: String

        func match(_ query: String) -> Double? {
            let byID = FuzzyMatcher.score(query: query, candidate: id)
            let byLabel = FuzzyMatcher.score(query: query, candidate: suggestion.label)
            switch (byID, byLabel) {
            case let (.some(a), .some(b)): return max(a, b)
            case let (.some(a), .none): return a
            case let (.none, .some(b)): return b
            case (.none, .none): return nil
            }
        }
    }

    private func entries(of catalog: Verb.Catalog, in references: CommandReferences) -> [Candidate] {
        switch catalog {
        case .openables:
            let apps = references.apps.values.map {
                Candidate(suggestion: CommandSuggestion(command: "open \($0.id)", label: $0.label, kind: .app), id: $0.id)
            }
            let urls = references.urls.values.map {
                Candidate(suggestion: CommandSuggestion(command: "open \($0.id)", label: $0.label, kind: .url), id: $0.id)
            }
            return apps + urls
        case .modes:
            return references.modeIds.map { id in
                Candidate(
                    suggestion: CommandSuggestion(command: "mode \(id)", label: modeLabels[id] ?? id, kind: .mode),
                    id: id
                )
            }
        case .workflows:
            return references.workflowIds.map { id in
                Candidate(
                    suggestion: CommandSuggestion(command: "run \(id)", label: workflowLabels[id] ?? id, kind: .workflow),
                    id: id
                )
            }
        case .hooks:
            return references.hooks.values.map {
                Candidate(suggestion: CommandSuggestion(command: "hook \($0.id)", label: $0.label, kind: .hook), id: $0.id)
            }
        }
    }

    // MARK: - As-typed row

    private func asTypedSuggestion(for intent: CommandIntent, command: String) -> CommandSuggestion {
        switch intent {
        case let .openApp(entry):
            return CommandSuggestion(command: command, label: entry.label, kind: .app)
        case let .openURL(entry):
            return CommandSuggestion(command: command, label: entry.label, kind: .url)
        case let .applyMode(modeId):
            return CommandSuggestion(command: command, label: modeLabels[modeId] ?? modeId, kind: .mode)
        case let .runAction(actionId):
            return CommandSuggestion(command: command, label: workflowLabels[actionId] ?? actionId, kind: .workflow)
        case let .runHook(entry):
            return CommandSuggestion(command: command, label: entry.label, kind: .hook)
        case .captureNote, .searchNotes, .listNotes, .readNote,
             .googleSearch, .youtubeSearch, .spotifyControl, .webOpen, .openProject,
             .listApps, .runSpeedTest, .quitAllApps, .createCalendarEvent, .cloneRepository,
             .createLinearIssue, .createSpotifyPlaylist, .scaffoldProject, .sendMessage:
            let verb = splitFirstToken(command).first
            let label = Verb.all.first { $0.token == verb }?.description ?? command
            return CommandSuggestion(command: command, label: label, kind: .command)
        }
    }

    // MARK: - Helpers

    private static func collapseWhitespace(_ input: String) -> String {
        input.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    private func splitFirstToken(_ input: String) -> (first: String, remainder: String) {
        guard let range = input.rangeOfCharacter(from: .whitespaces) else {
            return (input.lowercased(), "")
        }
        let first = String(input[..<range.lowerBound]).lowercased()
        let remainder = String(input[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        return (first, remainder)
    }

    /// The verb table: one row per parser verb, in the supported-patterns order
    /// (the empty-query listing). Kept alongside ``DirectCommandParser``'s
    /// grammar — a verb added there needs a row here.
    private struct Verb {
        enum Catalog: CaseIterable {
            case openables
            case modes
            case workflows
            case hooks
        }

        enum Argument {
            case references(Catalog)
            case freeText
            case none
        }

        let token: String
        let description: String
        let pattern: String
        let argument: Argument

        var templateSuggestion: CommandSuggestion {
            switch argument {
            case .none:
                // Argument-free verbs are complete commands already.
                return CommandSuggestion(command: token, label: description, detail: pattern, kind: .command)
            case .freeText, .references:
                return CommandSuggestion(
                    command: "\(token) ",
                    label: description,
                    detail: pattern,
                    kind: .pattern,
                    requiresArgument: true
                )
            }
        }

        static let all: [Verb] = [
            Verb(token: "open", description: "Open an app or URL", pattern: "open <app|url>", argument: .references(.openables)),
            Verb(token: "mode", description: "Switch mode", pattern: "mode <id>", argument: .references(.modes)),
            Verb(token: "note", description: "Capture a note", pattern: "note <text>", argument: .freeText),
            Verb(token: "project", description: "Open a project in the editor", pattern: "project <path>", argument: .freeText),
            Verb(token: "search", description: "Search notes", pattern: "search <text>", argument: .freeText),
            Verb(token: "google", description: "Google search", pattern: "google <query>", argument: .freeText),
            Verb(token: "youtube", description: "YouTube search", pattern: "youtube <query>", argument: .freeText),
            Verb(token: "clone", description: "Clone a repository", pattern: "clone <url>", argument: .freeText),
            Verb(token: "spotify", description: "Control Spotify playback", pattern: "spotify <action>", argument: .freeText),
            Verb(token: "web", description: "Open a web address", pattern: "web <url>", argument: .freeText),
            Verb(token: "hook", description: "Run a hook", pattern: "hook <id>", argument: .references(.hooks)),
            Verb(token: "run", description: "Run a quick action", pattern: "run <action>", argument: .references(.workflows)),
            Verb(token: "apps", description: "List installed apps", pattern: "apps", argument: .none),
            Verb(token: "speedtest", description: "Test internet speed", pattern: "speedtest", argument: .none),
            Verb(token: "quit-all", description: "Quit all open apps", pattern: "quit-all", argument: .none),
            // Deliberately absent: `notes-list` and `notes-read <path>` (NIC-162).
            // The parser accepts them, but they return data to a caller rather
            // than doing anything the palette could show, so advertising them here
            // would offer the user a command with no visible result. Add rows when
            // a surface renders them.
        ]
    }

    /// Deduplicates by command string (highest score wins) and orders the
    /// survivors: score, then kind priority, then label, then command — every
    /// comparison total, so the ranking is reproducible.
    private struct Collector {
        private var best: [String: (suggestion: CommandSuggestion, score: Double)] = [:]

        mutating func add(_ suggestion: CommandSuggestion, score: Double) {
            if let existing = best[suggestion.command], existing.score >= score { return }
            best[suggestion.command] = (suggestion, score)
        }

        mutating func add(_ candidate: Candidate, score: Double) {
            add(candidate.suggestion, score: score)
        }

        func ranked(limit: Int) -> [CommandSuggestion] {
            best.values
                .sorted { left, right in
                    if left.score != right.score { return left.score > right.score }
                    let leftPriority = Self.kindPriority[left.suggestion.kind, default: .max]
                    let rightPriority = Self.kindPriority[right.suggestion.kind, default: .max]
                    if leftPriority != rightPriority { return leftPriority < rightPriority }
                    if left.suggestion.label != right.suggestion.label {
                        return left.suggestion.label < right.suggestion.label
                    }
                    return left.suggestion.command < right.suggestion.command
                }
                .prefix(limit)
                .map { $0.suggestion }
        }

        /// Launch-something beats meta-rows when scores tie.
        private static let kindPriority: [CommandSuggestion.Kind: Int] = [
            .app: 0, .url: 1, .workflow: 2, .mode: 3, .hook: 4, .command: 5, .pattern: 6,
        ]
    }
}
