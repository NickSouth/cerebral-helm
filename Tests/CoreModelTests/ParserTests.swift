import Foundation
import Testing

import CerebralCore

/// NIC-24: deterministic direct-command parser.

private let vscode = ReferenceEntry(id: "vscode", label: "Visual Studio Code", target: "com.microsoft.VSCode")
private let github = ReferenceEntry(id: "github", label: "GitHub", target: "https://github.com")
private let ondraft = ReferenceEntry(id: "ondraft-dev", label: "On Draft (dev)", target: "scripts/ondraft-dev.sh")

private func sampleParser() -> DirectCommandParser {
    let references = CommandReferences(
        apps: [vscode],
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
