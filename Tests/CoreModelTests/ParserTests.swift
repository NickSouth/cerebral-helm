import Foundation
import Testing

import CerebralCore

/// NIC-24: deterministic direct-command parser.

private let vscode = ReferenceEntry(id: "vscode", label: "Visual Studio Code", target: "com.microsoft.VSCode")
/// The shipped catalog configures the Notes app under exactly this id, so it is
/// the live collision case for any note-related verb (NIC-162).
private let notes = ReferenceEntry(id: "notes", label: "Notes", target: "com.apple.Notes")
private let github = ReferenceEntry(id: "github", label: "GitHub", target: "https://github.com")
private let ondraft = ReferenceEntry(id: "ondraft-dev", label: "On Draft (dev)", target: "scripts/ondraft-dev.sh")

private func sampleParser() -> DirectCommandParser {
    let references = CommandReferences(
        apps: [vscode, notes],
        urls: [github],
        hooks: [ondraft],
        modeIds: ["developer", "executive"],
        workflowIds: ["open-developer-layout", "morning-brief"]
    )
    return DirectCommandParser(references: references)
}

// MARK: - AC-24.1 supported grammar resolves to typed intents

@Test("each supported verb resolves to the expected intent")
func supportedGrammarResolves() {
    let parser = sampleParser()

    #expect(parser.parse("open vscode") == .parsed(.openApp(vscode)))
    #expect(parser.parse("open github") == .parsed(.openURL(github)))
    #expect(parser.parse("mode developer") == .parsed(.applyMode(modeId: "developer")))
    #expect(parser.parse("note pick up milk") == .parsed(.captureNote(text: "pick up milk")))
    #expect(parser.parse("project /Users/x/Projects/foo") == .parsed(.openProject(repoPath: "/Users/x/Projects/foo")))
    #expect(parser.parse("search updater config") == .parsed(.searchNotes(query: "updater config")))
    #expect(parser.parse("hook ondraft-dev") == .parsed(.runHook(ondraft)))
    #expect(parser.parse("run open-developer-layout") == .parsed(.runAction(actionId: "open-developer-layout")))
    #expect(parser.parse("apps") == .parsed(.listApps))
    #expect(parser.parse("speedtest") == .parsed(.runSpeedTest))
    #expect(parser.parse("notes-list") == .parsed(.listNotes(limit: nil)))
    #expect(parser.parse("notes-read inbox/ch-idea-001.md") == .parsed(.readNote(path: "inbox/ch-idea-001.md")))
}

@Test("the note read verbs are addressable but unadvertised until a surface renders them (NIC-162)")
func noteLibraryGrammar() {
    let parser = sampleParser()

    // A note authored elsewhere is titled by its filename, so paths carry spaces:
    // the whole remainder is the path, not just the first token.
    #expect(
        parser.parse("notes-read inbox/Hull Plating.md")
            == .parsed(.readNote(path: "inbox/Hull Plating.md"))
    )
    // The cap is part of the grammar, so every caller can ask for one.
    #expect(parser.parse("notes-list") == .parsed(.listNotes(limit: nil)))
    #expect(parser.parse("notes-list 50") == .parsed(.listNotes(limit: 50)))
    // A cap that isn't one never executes: a listing that ignored its argument
    // would misreport what it returned.
    for bad in ["notes-list abc", "notes-list 0", "notes-list -3"] {
        guard case let .unrecognized(unrecognized) = parser.parse(bad) else {
            Issue.record("\(bad) must not execute")
            continue
        }
        #expect(unrecognized.suggestions == ["notes-list", "notes-list 50"])
    }
    // An argument-less read never executes.
    #expect(
        parser.parse("notes-read")
            == .unrecognized(UnrecognizedInput(
                reason: .missingArgument(verb: "notes-read"),
                suggestions: DirectCommandParser.supportedPatterns
            ))
    )
    // The verbs must not shadow a reference the user already owns: `notes` is the
    // Notes app, and it keeps resolving as one.
    #expect(parser.parse("open notes") == .parsed(.openApp(notes)))
    #expect(
        parser.parse("notes")
            == .unrecognized(UnrecognizedInput(
                reason: .unknownVerb("notes"),
                suggestions: DirectCommandParser.supportedPatterns
            ))
    )
    // Deliberately absent from the advertised grammar: both return data to a
    // caller, and the palette has nothing to show for them yet.
    #expect(!DirectCommandParser.supportedPatterns.contains { $0.hasPrefix("notes-") })
}

@Test("project takes the whole remainder as the path and requires an argument (NIC-131)")
func projectGrammar() {
    let parser = sampleParser()

    // Paths may contain spaces — the whole remainder is the path, not just the first token.
    #expect(
        parser.parse("project /Users/x/My Projects/demo")
            == .parsed(.openProject(repoPath: "/Users/x/My Projects/demo"))
    )
    // An argument-less `project` never executes.
    if case .parsed = parser.parse("project") {
        Issue.record("argument-less project must not execute")
    }
}

@Test("google takes the whole remainder as the query and requires an argument (NIC-134)")
func googleGrammar() {
    let parser = sampleParser()

    // Queries contain spaces — the whole remainder is the query.
    #expect(
        parser.parse("google where to watch Dune: Part Two")
            == .parsed(.googleSearch(query: "where to watch Dune: Part Two"))
    )
    // An argument-less `google` never executes.
    if case .parsed = parser.parse("google") {
        Issue.record("argument-less google must not execute")
    }
}

@Test("spotify takes the action as the remainder and requires an argument (NIC-133)")
func spotifyGrammar() {
    let parser = sampleParser()

    #expect(parser.parse("spotify pause") == .parsed(.spotifyControl(action: "pause")))
    #expect(parser.parse("spotify next") == .parsed(.spotifyControl(action: "next")))
    // An argument-less `spotify` never executes.
    if case .parsed = parser.parse("spotify") {
        Issue.record("argument-less spotify must not execute")
    }
}

@Test("web takes the whole remainder as the url and requires an argument (NIC-127)")
func webGrammar() {
    let parser = sampleParser()

    // The whole remainder is the url (may carry query params with `?`/`&`).
    #expect(
        parser.parse("web https://news.example.com/story?id=42&ref=home")
            == .parsed(.webOpen(url: "https://news.example.com/story?id=42&ref=home"))
    )
    // An argument-less `web` never executes.
    if case .parsed = parser.parse("web") {
        Issue.record("argument-less web must not execute")
    }
}

@Test("an unresolved workflow id is unrecognized and suggests configured actions")
func unresolvedWorkflowIsRejected() {
    let result = sampleParser().parse("run banana")
    guard case let .unrecognized(unrecognized) = result else {
        Issue.record("expected unrecognized, got \(result)")
        return
    }
    #expect(unrecognized.reason == .unresolvedReference(verb: "run", token: "banana"))
    #expect(unrecognized.suggestions == ["morning-brief", "open-developer-layout"])
}

@Test("parsing is deterministic and tolerates surrounding whitespace and verb case")
func parsingIsDeterministic() {
    let parser = sampleParser()
    let first = parser.parse("  MODE   developer  ")
    let second = parser.parse("  MODE   developer  ")
    #expect(first == second)
    #expect(first == .parsed(.applyMode(modeId: "developer")))
    // Free-text keeps internal spacing but trims the ends.
    #expect(parser.parse("note   buy   milk  ") == .parsed(.captureNote(text: "buy   milk")))
}

// MARK: - AC-24.2 unknown input returns suggestions without execution

@Test("an unknown verb is unrecognized and offers supported patterns")
func unknownVerbIsRejected() {
    let result = sampleParser().parse("teleport home")
    guard case let .unrecognized(unrecognized) = result else {
        Issue.record("expected unrecognized, got \(result)")
        return
    }
    #expect(unrecognized.reason == .unknownVerb("teleport"))
    #expect(unrecognized.suggestions == DirectCommandParser.supportedPatterns)
}

@Test("an unresolved reference is unrecognized and suggests valid ids")
func unresolvedReferenceIsRejected() {
    let result = sampleParser().parse("mode banana")
    guard case let .unrecognized(unrecognized) = result else {
        Issue.record("expected unrecognized, got \(result)")
        return
    }
    #expect(unrecognized.reason == .unresolvedReference(verb: "mode", token: "banana"))
    #expect(unrecognized.suggestions == ["developer", "executive"])
}

@Test("empty and argument-less input never produces an executable intent")
func emptyAndMissingArgumentsAreRejected() {
    let parser = sampleParser()
    #expect(parser.parse("   ") == .unrecognized(UnrecognizedInput(reason: .emptyInput, suggestions: DirectCommandParser.supportedPatterns)))

    if case .parsed = parser.parse("note") {
        Issue.record("argument-less note must not execute")
    }
    if case let .unrecognized(unrecognized) = parser.parse("hook") {
        #expect(unrecognized.reason == .missingArgument(verb: "hook"))
    } else {
        Issue.record("argument-less hook should be unrecognized")
    }
}

// MARK: - AC-24.3 ambiguous references produce a reviewable error

@Test("a token matching both app and url catalogs is ambiguous, not executed")
func ambiguousReferenceIsReported() {
    let shared = "github"
    let references = CommandReferences(
        apps: [ReferenceEntry(id: shared, label: "GitHub Desktop", target: "com.github.GitHubClient")],
        urls: [ReferenceEntry(id: shared, label: "GitHub", target: "https://github.com")],
        modeIds: ["developer"]
    )
    let result = DirectCommandParser(references: references).parse("open github")

    #expect(result == .ambiguous(AmbiguousReference(
        verb: "open",
        token: "github",
        candidates: [
            AmbiguousReference.Candidate(kind: "app", id: "github"),
            AmbiguousReference.Candidate(kind: "url", id: "github"),
        ]
    )))
}

// MARK: - Integration with the on-disk reference catalog

private func configDirectory() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // CoreModelTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // repository root
        .appendingPathComponent("config", isDirectory: true)
}

@Test("the loader reads the repository reference catalog and modes")
func loaderReadsRepositoryCatalog() throws {
    let references = try ReferenceCatalogLoader.load(configDirectory: configDirectory())

    #expect(references.apps["vscode"]?.target == "com.microsoft.VSCode")
    #expect(references.urls["github"]?.target == "https://github.com")
    #expect(references.hooks["ondraft-dev"] != nil)
    #expect(references.modeIds.contains("developer"))
    #expect(references.workflowIds.contains("open-developer-layout"))

    let parser = DirectCommandParser(references: references)
    #expect(parser.parse("open vscode") == .parsed(.openApp(references.apps["vscode"]!)))
    #expect(parser.parse("mode developer") == .parsed(.applyMode(modeId: "developer")))
    #expect(parser.parse("run open-developer-layout") == .parsed(.runAction(actionId: "open-developer-layout")))
}
