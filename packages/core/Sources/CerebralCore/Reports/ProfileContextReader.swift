import Foundation

/// Reads `profile/` into the ~1–2K tokens that make a brief personal (NIC-251).
///
/// **This is the highest-leverage part of the daily brief, and it is not a feature.** Roughly a
/// hundred tokens of profile turned a flat recitation of weather metrics into "New England is clear
/// today… perfect conditions for a round if the weather holds. […] Protect the morning for deep work
/// on the local LLM integration" — with deliberation still off, at no latency cost, and with *fewer*
/// output tokens. The rule it established is that for composition, **context substitutes for
/// reasoning**: "empty day + good weather + he golfs" needs the fact, not the thinking.
///
/// **No retrieval.** At this size the folder is included wholesale. RAG is for the large corpora and
/// the full vault (phase 3); running an embedding search over four short notes would be machinery in
/// place of a read.
///
/// **Everything admitted has passed ``ModelContextPolicy``.** Profile notes default to
/// `sensitivity: sensitive` and `cloudPolicy: deny`, and inference is local, so nothing is excluded
/// in practice today — which is exactly why the filter is worth having now rather than later.
public struct ProfileContextReader: Sendable {
    /// The folder whose notes are the "who I am" layer, per `knowledge-template/profile/README.md`.
    public static let folder = "profile"

    /// The recommended ceiling, in tokens.
    ///
    /// **A discipline, not a limit.** The measured win came from four short, highly relevant facts,
    /// and irrelevant context measurably distracts — so the ceiling exists to stop a profile growing
    /// into a corpus, not because 2,001 tokens would fail. The passive tier's budget is otherwise
    /// wide open: it sends no tool manifest, so the ~4.5K the agent tier spends on tools is free.
    public static let tokenBudget = 2_000

    /// Characters per token, approximately.
    ///
    /// Deliberately an estimate. Counting exactly would mean shipping the model's tokenizer into
    /// the portable core to enforce a ceiling that is advisory anyway — precision bought at the cost
    /// of a dependency, in service of a number that is a judgement. Four is the usual figure for
    /// English prose and errs slightly toward over-counting, which is the safe direction here.
    static let charactersPerToken = 4

    private let knowledge: any KnowledgeService
    private let destination: ModelDestination

    public init(knowledge: any KnowledgeService, destination: ModelDestination = .local) {
        self.knowledge = knowledge
        self.destination = destination
    }

    /// The admitted profile notes, rendered as one block of prose, or nil when there are none.
    ///
    /// Nil rather than an empty string: "nothing has been written" is a fact, and an empty value is
    /// something a composer told to use what it is given would dutifully describe.
    public func read() async throws -> String? {
        // The whole listing, then filtered by folder. `KnowledgeService.list` takes a limit but no
        // folder scope, and a limit applied before filtering would silently drop profile notes on a
        // large vault — the cheap read here is the wrong kind of cheap.
        let listing = try await knowledge.list(NoteListRequest(limit: nil))

        let candidates = listing.entries
            .filter { $0.folder == Self.folder }
            // Freshest first. A profile note updated recently reflects current reality — the
            // `currentFocus` that makes a brief timely — so if the budget forces a choice, the stale
            // note is the one to lose. Path breaks ties so the ordering is total and the prompt
            // prefix stays stable between runs.
            .sorted {
                switch ($0.updated, $1.updated) {
                case let (lhs?, rhs?) where lhs != rhs: return lhs > rhs
                default: return $0.path < $1.path
                }
            }

        var sections: [String] = []
        var characters = 0
        let ceiling = Self.tokenBudget * Self.charactersPerToken

        for entry in candidates {
            // Checked BEFORE the read where it can be: a note excluded on `sensitivity` alone never
            // has its body loaded at all, rather than being read and then discarded.
            if case .excluded = ModelContextPolicy.admits(
                sensitivity: entry.sensitivity, cloudPolicy: nil, to: .local
            ), destination == .local {
                continue
            }

            guard let note = try? await knowledge.read(NoteReadRequest(path: entry.path)) else {
                // One unreadable note is not a failed profile: the others still describe the person.
                continue
            }
            guard ModelContextPolicy.admits(
                sensitivity: note.frontmatter["sensitivity"] ?? entry.sensitivity,
                cloudPolicy: note.frontmatter["cloudPolicy"],
                to: destination
            ).isAdmitted else { continue }

            let section = Self.render(title: note.title, body: note.body)
            guard !section.isEmpty else { continue }

            // Whole notes only. A profile truncated mid-sentence is worse than a shorter one: the
            // model cannot tell a cut-off fact from a complete one, and half of "he golfs whenever
            // the weather allows" is a different claim.
            if characters + section.count > ceiling, !sections.isEmpty { break }
            sections.append(section)
            characters += section.count
            if characters >= ceiling { break }
        }

        return sections.isEmpty ? nil : sections.joined(separator: "\n\n")
    }

    /// One note as a titled section. The title is carried because it is what tells the model which
    /// facts belong together — "Health" and "Work" read very differently as an undifferentiated run
    /// of sentences.
    static func render(title: String, body: String) -> String {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let heading = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return heading.isEmpty ? trimmed : "## \(heading)\n\(trimmed)"
    }
}
