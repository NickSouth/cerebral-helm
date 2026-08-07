import Foundation
import Testing

import CerebralCore

/// NIC-168: deterministic suggestion ranking over the live command catalogs.

private let chrome = ReferenceEntry(id: "chrome", label: "Google Chrome", target: "com.google.Chrome")
private let vscode = ReferenceEntry(id: "vscode", label: "Visual Studio Code", target: "com.microsoft.VSCode")
private let notesApp = ReferenceEntry(id: "notes", label: "Notes", target: "com.apple.Notes")
private let github = ReferenceEntry(id: "github", label: "GitHub", target: "https://github.com")
private let ondraft = ReferenceEntry(id: "ondraft-dev", label: "On Draft (dev)", target: "scripts/ondraft-dev.sh")

private func sampleReferences() -> CommandReferences {
    CommandReferences(
        apps: [chrome, vscode, notesApp],
        urls: [github],
        hooks: [ondraft],
        modeIds: ["developer", "school"],
        workflowIds: ["open-developer-layout", "morning-brief"]
    )
}

private func sampleEngine(store: CommandReferenceStore = CommandReferenceStore(sampleReferences())) -> CommandSuggestionEngine {
    CommandSuggestionEngine(
        referenceStore: store,
        modeLabels: ["developer": "Developer", "school": "School"],
        workflowLabels: ["open-developer-layout": "Open Developer Layout", "morning-brief": "Morning Brief"]
    )
}

// MARK: - Empty query

@Test("an empty query lists the supported grammar as template rows")
func emptyQueryListsPatterns() {
    let suggestions = sampleEngine().suggest("   ")

    #expect(suggestions.count == CommandSuggestionEngine.defaultLimit)
    #expect(suggestions[0].label == "Open an app or URL")
    #expect(suggestions[0].command == "open ")
    #expect(suggestions[0].kind == .pattern)
    #expect(suggestions[0].requiresArgument)
    #expect(suggestions[0].detail == "open <app|url>")
}

// MARK: - Typo tolerance (AC3)

@Test("a typo'd bare token resolves to the intended open command")
func typoBareToken() {
    let suggestions = sampleEngine().suggest("chrme")

    #expect(suggestions.first?.command == "open chrome")
    #expect(suggestions.first?.label == "Google Chrome")
    #expect(suggestions.first?.kind == .app)
    #expect(suggestions.first?.requiresArgument == false)
}

@Test("a typo'd verb corrects into the intended free-text command")
func typoVerbCorrects() {
    let suggestions = sampleEngine().suggest("serach build logs")

    #expect(suggestions.first?.command == "search build logs")
    #expect(suggestions.first?.label == "Search notes")
    #expect(suggestions.first?.kind == .command)
}

@Test("matching is case-insensitive")
func caseInsensitive() {
    #expect(sampleEngine().suggest("Chrome").first?.command == "open chrome")
}

// MARK: - As-typed input always ranks first

@Test("cleanly parsing free text is never hijacked by a fuzzy match")
func asTypedFreeTextFirst() {
    let suggestions = sampleEngine().suggest("note buy milk")

    #expect(suggestions.first?.command == "note buy milk")
    #expect(suggestions.first?.label == "Capture a note")
    #expect(suggestions.first?.kind == .command)
}

@Test("a google search for an app name tops the list, with the app right below")
func asTypedBeatsLabelMatch() {
    let suggestions = sampleEngine().suggest("google chrome")

    #expect(suggestions.count >= 2)
    #expect(suggestions[0].command == "google chrome")
    #expect(suggestions[0].kind == .command)
    #expect(suggestions[1].command == "open chrome")
    #expect(suggestions[1].kind == .app)
}

@Test("an exactly resolving command appears once, first")
func asTypedDeduplicates() {
    let suggestions = sampleEngine().suggest("open github")

    #expect(suggestions.first?.command == "open github")
    #expect(suggestions.first?.label == "GitHub")
    #expect(suggestions.filter { $0.command == "open github" }.count == 1)
}

// MARK: - Verb-scoped argument completion

@Test("a known verb scopes completion to its catalog")
func verbScopedCompletion() {
    let suggestions = sampleEngine().suggest("open g")

    // "github" (id prefix) covers more of its candidate than "g" does of
    // "google chrome", so it ranks first; both stay in the open catalog.
    #expect(suggestions.first?.command == "open github")
    #expect(suggestions.contains { $0.command == "open chrome" })
    #expect(!suggestions.contains { $0.command.hasPrefix("mode ") })
}

@Test("a bare reference verb offers its template and the whole catalog")
func bareVerbEnumeratesCatalog() {
    let suggestions = sampleEngine().suggest("mode")

    // The fill-in template leads (safe on Enter), the catalog follows, ordered.
    #expect(suggestions.first?.command == "mode ")
    #expect(suggestions.first?.requiresArgument == true)
    let developer = suggestions.firstIndex { $0.command == "mode developer" }
    let school = suggestions.firstIndex { $0.command == "mode school" }
    #expect(developer != nil && school != nil)
    #expect(developer! < school!)
    #expect(suggestions[developer!].label == "Developer")
}

// MARK: - Bare tokens match every catalog

@Test("a bare token surfaces matches across catalogs, best first")
func bareTokenAcrossCatalogs() {
    let suggestions = sampleEngine().suggest("developer")

    let mode = suggestions.firstIndex { $0.command == "mode developer" }
    let workflow = suggestions.firstIndex { $0.command == "run open-developer-layout" }
    #expect(mode != nil && workflow != nil)
    // Exact mode id beats the workflow's word-boundary label match.
    #expect(mode! < workflow!)
    #expect(suggestions[workflow!].label == "Open Developer Layout")
}

@Test("an exact reference id beats a same-name verb correction")
func referenceBeatsVerbTypo() {
    // "notes" is one edit from the `note` verb but exactly the Notes app.
    let suggestions = sampleEngine().suggest("notes")

    #expect(suggestions.first?.command == "open notes")
    #expect(suggestions.first?.kind == .app)
}

@Test("a prefix of an argument-free verb suggests the runnable command")
func arglessVerbPrefix() {
    let suggestions = sampleEngine().suggest("quit")

    #expect(suggestions.first?.command == "quit-all")
    #expect(suggestions.first?.kind == .command)
    #expect(suggestions.first?.requiresArgument == false)
}

// MARK: - Determinism and bounds

@Test("equal scores break ties by kind priority")
func kindPriorityTieBreak() {
    let references = CommandReferences(
        apps: [ReferenceEntry(id: "zeta", label: "Zeta", target: "com.example.zeta")],
        modeIds: [],
        workflowIds: ["zeta"]
    )
    let engine = CommandSuggestionEngine(referenceStore: CommandReferenceStore(references))

    let suggestions = engine.suggest("zeta")

    let app = suggestions.firstIndex { $0.command == "open zeta" }
    let workflow = suggestions.firstIndex { $0.command == "run zeta" }
    #expect(app != nil && workflow != nil)
    #expect(app! < workflow!)
}

@Test("the limit caps the list and an unmatched query returns nothing")
func limitAndNoMatch() {
    let engine = sampleEngine()

    #expect(engine.suggest("", limit: 3).count == 3)
    #expect(engine.suggest("o", limit: 2).count <= 2)
    #expect(engine.suggest("zzzzzz").isEmpty)
}

// MARK: - Recent direct commands (PRD §9.4)

@Test("recentSuggestions keeps only still-resolvable, re-runnable commands, deduped in order")
func recentSuggestionsFilterAndDedupe() {
    let recents = sampleEngine().recentSuggestions([
        "open chrome", // resolvable app — kept
        "note buy milk", // free text — excluded, typed text never resurfaces
        "open chrome", // duplicate — deduped
        "mode developer", // resolvable mode — kept, labeled
        "open gone-app", // unresolvable reference — dropped
        "speedtest", // argument-free — kept
    ])

    #expect(recents.map(\.command) == ["open chrome", "mode developer", "speedtest"])
    #expect(recents[0].label == "Google Chrome")
    #expect(recents[0].kind == .app)
    #expect(recents[1].label == "Developer")
    #expect(recents[2].kind == .command)
}

@Test("recentSuggestions honors its limit")
func recentSuggestionsLimit() {
    let recents = sampleEngine().recentSuggestions(
        ["open chrome", "open vscode", "open notes", "mode developer"], limit: 2
    )

    #expect(recents.map(\.command) == ["open chrome", "open vscode"])
}

// MARK: - Live catalog reload (NIC-146 parity)

@Test("a reference minted mid-session becomes suggestible without a new engine")
func liveReload() {
    let store = CommandReferenceStore(sampleReferences())
    let engine = sampleEngine(store: store)

    #expect(!engine.suggest("slck").contains { $0.command == "open slack" })

    var references = sampleReferences()
    references = CommandReferences(
        apps: Array(references.apps.values) + [ReferenceEntry(id: "slack", label: "Slack", target: "com.tinyspeck.slackmacgap")],
        urls: Array(references.urls.values),
        hooks: Array(references.hooks.values),
        modeIds: Array(references.modeIds),
        workflowIds: Array(references.workflowIds)
    )
    store.reload(references)

    #expect(engine.suggest("slck").first?.command == "open slack")
}
