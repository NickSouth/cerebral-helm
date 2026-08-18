# Agent charter — Research Analyst

**Status:** Proposal, 2026-08-11 — not yet agreed with owner
**Phase:** 4 (scoped agents) — see [../PLAN.md](../PLAN.md)

## What it is for (owner, 2026-08-11)

> "I want to know more about my nutrition" → finds several peer-reviewed sources,
> deep-dives, and produces a compressed report **as it applies to me**, filed in
> Obsidian — **so that Heimlich can use it later.**

The worked example matters more than the description. Weeks after the research is
done, in an unrelated conversation:

> — "I'm about to go grocery shopping, what should I get?"
> — "More protein, based on your research."

**The reports are not the deliverable. They are inputs to other agents.** Everything
below follows from that:

- Notes must be written for **two readers**: the owner (prose) and other agents
  (structured claims). A 2,000-word report is not something Heimlich should re-read
  and re-summarise to answer a grocery question.
- The report is **personalised**, not a neutral literature review. "As it applies to
  me" means the analyst reads `profile/` — age, activity, goals, constraints — and
  applies findings to them.
- **Retrieval is what unlocks this.** Heimlich surfacing the right note mid-conversation
  needs semantic search over the research folder — phase 3 of the plan. The Research
  Analyst is the agent that most benefits from phase 3, and its output is what makes
  phase 3 worth having. They should be sequenced together.

### Note format — the downstream contract

Every research note carries, at fixed positions:

| Part | Purpose |
|---|---|
| **Headline title** stating the *finding*, not the topic | "Protein at 1.6 g/kg supports strength gains" beats "Protein research". A finding is retrievable and usable; a topic is a filing label. |
| **Key findings** — structured, in frontmatter | What another agent reads. Short, declarative, each traceable to a source. |
| **Applies-to-me** section | The personalisation, kept separate from what the sources actually said. |
| **Body** — the compressed report | For the owner to read. |
| **Sources** with provenance | URLs, retrieval date, `capturedBy: research-analyst`. |

Keeping *what the sources said* separate from *what this means for me* is the single
most important structural rule here, because the second is the analyst's inference
and the first is not. A downstream agent should be able to cite either and know which
it is holding.

### One honest note on health topics

Nutrition and health are the likeliest early subjects, and they are where source
quality varies most and where "frames rather than prescribes" earns its keep. The
useful design response is not caution in tone but **traceability**: Heimlich should be
able to say "based on [source], at [strength of evidence]", not merely "based on your
research". That is a property of the note format above, not of the persona.

## This one breaks the pattern, deliberately

The first two agents converged on the same shape: a typed SQLite store holding a
plan and its actuals, three protocols, additive history. **This agent should not
have that**, and saying so is more useful than forcing the symmetry.

Its durable output is *notes* — sources read, claims assessed, questions still open —
and the vault already holds notes. `knowledge-template/reference/` exists for exactly
this: "durable reference material… notes you return to." Adding a research database
alongside it would create a second home for the same content, and the vault version
is the one the owner can read, edit, and search in Obsidian.

**So: vault-native, minimal-to-no SQLite.** The asymmetry is the finding. Finance
needed a database because it reasons over numbers and time series. PM needed one
because plan-versus-actual is not otherwise recorded. Research produces prose, and
prose has a home.

## The safety problem this agent creates

**The Research Analyst is the injection surface for the entire system**, and this
should be designed for before it is built, not after.

It is the one agent that must read arbitrary, maximally untrusted web content — that
is its whole function. It is also the agent that writes into a shared vault which
*every other agent reads*. Those two facts together make a contamination path that no
other agent has:

```
hostile web page → analyst reads it → analyst writes a note →
    note enters the vault → Financial Advisor / PM / Heimlich read it as fact
```

The Financial Advisor's protection is that it has no egress. That does not help here,
because the analyst's *legitimate* function is to bring outside content in.

### Mitigations, all structural

1. **Content provenance on every analyst-written note.** Source URL, retrieval
   timestamp, and `capturedBy: research-analyst` in frontmatter. This is the same
   principle as [`ActionProvenance`](../../../packages/core/Sources/CerebralCore/Policy/ActionProvenance.swift)
   one layer down: *who determined this* travels with the thing itself, and the
   subject cannot claim otherwise.
2. **Other agents treat analyst-written notes as lower-trust than user-authored
   ones.** A claim sourced from the web and summarised by a model is not the same
   kind of object as something the owner wrote, and the system should be able to tell
   them apart at read time.
3. **Write scope is bounded to `reference/` and project research notes.** It may not
   write to `profile/`, finance notes, or anything another agent treats as
   authoritative personal fact.
4. **Claims require attribution.** A statement with no source is a flag, not a
   finding. This is also what makes the output useful for schoolwork.
5. **`sensitivity` and `cloudPolicy` are set on write**, defaulting conservatively —
   the fields already exist in note metadata.

## The six fields

### 1. Persona

Separates *what a source says* from *what is true* from *what the analyst concludes*,
and never blurs the three. Reports the strength of evidence, not just its direction.
Comfortable saying the literature is thin, mixed, or that a question is not settled —
which is the most common honest answer and the one a model is most tempted to skip.

### 2. Domain corpus — probably not a corpus

The owner's target: peer review, academic judgement, evaluating sources.

**Recommendation: a hand-authored rubric, not an ingested corpus.** Perhaps 1–2K
tokens covering evidence hierarchy, sample size and power, conflict of interest,
replication, preprint versus peer-reviewed, primary versus secondary, and citation
practice.

Two reasons. First, the profile experiment showed a few highly-relevant facts beat
volume — and methodology is exactly the kind of compact, stable knowledge that fits
in a rubric. Second, most good "how to evaluate sources" material lives on university
sites with unclear reuse terms, so a corpus here has a licensing problem a rubric
does not.

Revisit only if a real question turns out to need depth a rubric cannot carry.

### 3. Personal context

- `profile/` — durable facts, including field of study
- `reference/` — the accumulated research notes, which are this agent's memory
- Current courses via `course.list`, so academic work has context

### 4. Read tools

| Tool | Notes |
|---|---|
| `web.search` | **New.** Free-text search. This is the one agent that gets it. |
| `web.fetch` | **New.** Retrieve and extract a page's text. Distinct from `web.open`, which opens a browser for a human. |
| `scholar.search` | **New, proposed.** arXiv and/or Semantic Scholar — both free, structured, and citation-aware. Far better than general web search for academic work. |
| `note.search`, `note.read`, `note.list` | Existing — prior research |
| `course.list` | Existing |

`web.search` and `web.fetch` are the first tools in the system where **the model
chooses an arbitrary destination**. That is a real widening of the tool surface and
should be its own reviewed increment, not folded into agent work.

### 5. Action tools

- `note.capture` — write research notes to `reference/`, with provenance frontmatter

No other writes. No egress beyond fetching what it was asked to read.

### 6. Protocols

**1. `deep-dive`** — the core loop.

Take a question, search academic sources, read several, and synthesise **with
citations** into the note format above, personalised against `profile/`. Ends by
writing to the research folder on confirmation. Explicitly reports where sources
disagree rather than averaging them into false consensus, and says when the evidence
is thin.

Minutes, not seconds. This is the one place in the system where slow is acceptable —
and, per the phase-1 finding, the one agent where **thinking mode should be ON**.

**2. `quick-brief`** — the short mode (owner, 2026-08-11).

A fast scan producing a highlight report on a topic just raised in conversation. Not
peer-reviewed depth, and **it must say so**: same note format, but marked as a quick
brief so neither the owner nor a downstream agent mistakes it for a deep dive. Cites
what it saw.

The distinction between these two is carried in the note's own metadata, not just in
how it felt to run — otherwise a downstream agent cannot tell a scanned blog post
from a synthesis of five papers.

**2. `evaluate-source`** — where the rubric earns its place.

Given a paper, article, or claim: what kind of evidence is this, how strong, who
funded it, has it been replicated, what would change the conclusion. Useful for
coursework and for the owner's own technical decisions.

**3. `whats-known`** — a Report over accumulated notes on a topic.

What has already been established, what is still open, which sources were consulted.
Reads the vault rather than the web — the counterweight to an agent that would
otherwise always reach outward and never consolidate.

## Copyright

The analyst summarises third-party material. Summaries must be substantially shorter
and different from the source, quotes short and attributed, and the agent must never
reconstruct a work from accumulated excerpts across sessions. This matters
practically, not just legally: notes that are mostly quotation are worse notes.

## Open questions for the owner

1. **Search backend.** *(Corrected 2026-08-11 — an earlier draft of this charter
   called general web search "a paid dependency in most cases". That is wrong at
   personal volume.)*

   | Provider | Free tier | After |
   |---|---|---|
   | **Exa** | **20,000 req/month**, $20 signup + $10/month credit, **no card** | $7 / 1,000 |
   | Tavily | 1,000 credits/month, no card | ~$7.50–8 / 1,000 |
   | Serper | 2,500 queries | **$0.30 / 1,000** |
   | Brave | ~~5,000/month~~ **free tier removed Feb 2026** — $5 credit, card required, **no spending cap** | $0.003–0.005 / query |

   Realistic use here is tens to low hundreds of queries a month, which sits inside
   several free tiers with room to spare. Cost is not the constraint.

   Two things that actually matter more than price:

   - **Prefer an agent-oriented API that returns extracted text, not just links.**
     Tavily and Exa bundle search and extraction; raw link APIs leave you building
     fetch, HTML parsing, and JS-rendering handling yourself. That collapses
     `web.fetch` into the same dependency instead of a second subsystem.
   - **Avoid Brave for a personal project** — not on price, but because it now
     requires a card and bills overages with no spending cap.

   **Recommendation: Exa or Tavily**, still shipping `scholar.search` first so the
   injection handling is exercised on structured academic sources before arbitrary
   web pages arrive.
2. **Does this agent serve schoolwork, technical decisions, or both?** They want
   different defaults — academic rigour versus "which library should I use". Both is
   fine but the rubric and persona need to know which mode they are in.
3. ~~**Should analyst notes be visually distinct in Obsidian?**~~ **Decided** — they
   live in **their own folder, flat, all topics together** (owner, 2026-08-11). No
   per-topic subfolders: retrieval handles topic, and folder taxonomies go stale.
   Consistent with the rule that the vector index is disposable and the files are
   truth.

4. **Depth marker vocabulary.** `deep-dive` versus `quick-brief` needs to be a
   frontmatter field with a fixed vocabulary, since downstream agents branch on it.
   Proposed: `researchDepth: deep | brief`. Needs adding to note metadata, which
   currently carries `kind`, `sensitivity`, `cloudPolicy`, `status`, `reviewAfter`.

5. **How much of `profile/` does the analyst read?** Nutrition personalisation wants
   age, activity, goals and constraints — plausibly health data at
   `sensitivity: sensitive`. The profile README already says to split especially
   private material into its own note so it carries its own policy; this is the first
   agent that makes that split load-bearing rather than theoretical.

6. **Does `quick-brief` write a note at all, or just answer?** Writing everything
   fills the folder with low-value scans that then compete with deep dives in
   retrieval. **Recommendation: answer inline by default, write only on request** —
   otherwise the signal-to-noise of the research folder degrades, and that folder is
   the thing Heimlich depends on.
