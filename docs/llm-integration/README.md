# LLM integration — read this first

**Purpose:** everything decided and everything measured, in one place, so work can
resume without re-deriving any of it. Written 2026-08-11 at the end of the planning
and benchmarking session that produced it.

**Where the detail lives**

| Document | Contains |
|---|---|
| [PLAN.md](PLAN.md) | The architecture, the phases, and every measurement with its context |
| [agents/](agents/) | Four agent charters — the six fields, protocols, state, open questions |
| Linear milestone **CerebralHelm Local LLMs** | 16 epics, 76 pointed sub-issues, NIC-225 → NIC-317 |
| `evals/README.md` | How to re-run every measurement below |
| [ADR-009](../adr/ADR-009-model-provider-port.md) | The phase-0 decision: provider-neutral port, runtime abstraction, lifecycle ownership, local-first |

**This file is a decision log and an index. It is not the architecture** — when the
two disagree, PLAN.md and the charters win, and this file should be corrected.

---

## Where things stand

- **The grammar question is answered (`NIC-227`, 2026-08-20).** `NIC-247` is done — a
  `llamacpp` adapter sits behind `evals/lib/runtime.mjs` alongside Ollama, gated by
  `scripts/evals-runtime.test.mjs`. `NIC-248` is measured: findings **11–15** below,
  with a standing recommendation to keep Ollama by default and require a grammar only
  where document validity is load-bearing. `NIC-249` is built:
  `apps/mac/Sources/CerebralMacAdapters/LlamaCPPModelProvider.swift`, the first provider
  to report `enforcesResponseSchema: true` and the first to have earned it, with 20
  offline tests plus an opt-in live one (`CEREBRAL_LLAMACPP_TESTS=1`). **Nothing calls
  it** — `NIC-250` remains Backlog — which is the same shape phase 0 shipped the Ollama
  adapter in. No model profile points at it either: `profiles.json` keys are a fixed
  capability enum, so adopting this runtime means repointing an existing profile, and
  that is a product decision rather than a consequence of the adapter existing.

  Two shipped schemas were repaired to compile under GBNF at all, and the report block
  schema was bounded to stop a grammar running away in it. See the converter trap under
  *Traps that cost time* before adding any `pattern` to a model-facing input schema, and
  finding 16 before pointing a grammar at any schema.
- **Phase 0 is underway.** `NIC-225`: ADR-009 is written and the `ModelProvider` port
  exists in `packages/core/Sources/CerebralCore/Model/` (`NIC-241`, 2026-08-18) — protocol,
  request/usage types, `ModelDeadline`, `MockModelProvider`. The profile catalog is configuration
  (`NIC-243`): `config/models/profiles.json` + `model-profiles.schema.json`, resolved by
  `ModelProfileCatalog`, optional everywhere. The Ollama adapter (`NIC-242`) is built at
  `apps/mac/Sources/CerebralMacAdapters/OllamaModelProvider.swift` and **verified against a live
  Ollama 0.32.7** — a streamed completion in 9.0 s with real token accounting, plus 18 offline
  helper tests. Nothing calls any of it, by design: phase 0 is complete and the first caller is
  `NIC-250`. Everything else in the milestone remains Backlog.
- **Merged to `dev` (2026-08-18):** descriptor affordances as `5e95795` (#20); plan,
  charters and eval harness as `214813e` (#21). Full `node scripts/test.mjs` green on
  the contract change.
- **Installed locally:** Ollama 0.32.7, llama.cpp (Homebrew), and ~42 GB of models —
  `muse-glimmer:30b-mlx`, `qwen3.6:35b-mlx`, `qwen3-embedding:0.6b`.
- **Descriptor affordances are finished (`NIC-226`, 2026-08-20).** The seven fields the
  first pass left — five optional ones with no prose, plus `note.capture.sensitivity`
  and `window.arrange`'s `frame`, which had an enum and nothing else — now describe what
  omission does. `scripts/contracts-tool.test.mjs` gates it: every model-facing input
  field, nested ones included, must carry a description, so a new tool cannot ship bare.
  `evals/lib/score.mjs` gained a `"!"` expectation meaning **the argument must be
  absent**, without which an invented optional argument was invisible to scoring.

**Where to start:** `NIC-284`, the SimpleFIN adapter. It is the only ticket with a
clock on it — SimpleFIN serves a 90-day window, so financial trend history exists
only from whenever syncing begins, and it cannot be backfilled. It is also
standalone: a provider, a Keychain entry and a cache, no model involved.

Otherwise `NIC-225` (model provider port) is the root of everything else.

---

## The shape

**Three tiers, one spine.** The governing risk was that "add AI" becomes three
parallel systems duplicating context assembly, tool access and safety policy.

| Tier | Calls tools? | Reads how? |
|---|---|---|
| **Passive** — composes prose **and proposals**, executes nothing | No | Deterministically, via the Assembler |
| **Scoped agents** — narrow allowlist, narrow knowledge roots | Yes | Through read tools |
| **Heimlich** — widest allowlist, whole vault | Yes | Read tools + automatic retrieval |

**Heimlich is agent #5, not a fourth system.** He is a scoped agent whose scope is
"most things", plus a conversation surface, plus voice. Every phase is ordered to
make that true.

**Phase order — passive → agents → Heimlich** (owner). Deliberately not
difficulty-ordered: it is the order that teaches the most before the hardest surface
has to hold up.

---

## Decisions taken

All 2026-08-11 unless noted. Each is a decision, not a suggestion.

### Models and runtime

1. **`qwen3.6:35b-mlx` is the default model.** Tied with Muse Glimmer on accuracy
   (90.6% each pre-fix) and ~4.5x faster on decode. Glimmer was **not** re-measured
   after the descriptor fixes, so its numbers are pre-fix and not comparable.
2. **Thinking off everywhere except Research Analyst `deep-dive`.** Composition from
   a typed snapshot is rendering, not reasoning.
3. **Cap `num_ctx` per model role.** Context size is a memory decision.
4. **One resident 30B maximum**, plus the always-resident embedding model.
5. **`qwen3-embedding:0.6b`** for retrieval — ~639 MB, Apache 2.0, MTEB 70.7.
6. **The provider port abstracts the runtime, not just the model**, because
   llama.cpp and MLX differ on grammar-constrained decoding.
7. **Local-first.** A cloud escape hatch may exist but stays off by default and
   confirmation-gated.

### Architecture

8. **The Composer returns `blocks`; the system supplies the envelope.** Give a model
   only the part of a document that needs judgement.
9. **The passive tier may propose actions** via `proposal` blocks carrying
   `reportActionReference`s. It still executes nothing.
10. **Agents read through tools; the passive tier reads deterministically.** Each
    tier reads the way that suits it.
11. **Automatic retrieval, not tool-search, for Heimlich** — run every turn as part
    of context assembly. Tool search stays for deliberate lookup. Both are wanted.
12. **Allowlists are justified by least privilege**, not accuracy — see finding 3.
13. **Typed domain state, never freeform agent memory.** A model writing notes to
    itself is where hallucinations get persisted and compound.
14. **Supersession is detected on ingest, not by scanning** — one shared routine
    invoked from both entry points (an agent writing a note, and the Janitor filing
    a capture). Three outcomes: redundant → merge, conflicting → supersede,
    complementary → link.
15. **Background work produces a pending plan, never applied changes.** This is what
    lets the Janitor run passively without an exception to the confirmation policy.
16. **Seed report-started conversations with the snapshot, not the rendered blocks.**

### Safety

17. **`ActionProvenance` must not be weakened.** It already derives `modelProposed`
    from the `agent` source and a caller cannot supply it. It was written before
    there was a model.
18. **Risk and confirmation policy are absent from the model-facing manifest.**
    Telling a model an action is "destructive" invites it to reason about its own
    permissions — a decision that does not belong to it.
19. **The Financial Advisor gets no egress tools.** No `messages.send`, `web.open`,
    `url.open`, `hook.run`, `google.search`. Aggregation plus egress is the risk, not
    the model seeing balances.
20. **Heimlich MAY hold both `finance.*` and `web.search`** (owner, overriding the
    recommendation). Rationale accepted: worst case is balance figures in a search
    query, which the owner assessed as weird rather than harmful. *Noted at the time:
    `finance.transactions` is a behavioural profile rather than a number.*
21. **Market data is ticker-keyed only.** The model chooses a symbol, never a
    destination. Free-text web search is the Research Analyst's alone.
22. **Notes are never hard-deleted.** Archive relocates and re-flags. Deleting stays
    a manual action in Obsidian.
23. **Write boundary on Linear: workflow metadata yes, authored content no.** Status,
    cycle, estimate, priority, assignee, labels — never title or description. The
    line is *authorship*, not risk: a rewritten title loses the owner's thinking
    silently, because the confirmation shows a plausible replacement.
24. **Batch confirmation for bulk operations.** Forty individual prompts trains the
    user to approve without reading.
25. **The Research Analyst is the injection surface for the whole system** — it reads
    untrusted web content *and* writes into a vault every other agent reads.
    Mitigation is content provenance in frontmatter plus a retrieval trust filter.

### Phase 0 — the provider port (owner, 2026-08-18)

Recorded in full in [ADR-009](../adr/ADR-009-model-provider-port.md).

30. **Capability profiles, not functional roles, are the configuration keys** —
    `fast` / `balanced` / `deep` / `local`, per the tech stack's Model Profiles table.
    This *overrides* the working assumption in PLAN.md, which speaks in per-model roles.
    Each profile resolves to a model id, runtime id, `num_ctx` cap, residency directive
    and thinking flag. `local` is reserved for surfaces that must never leave the machine
    even if a cloud escape hatch is later enabled.
31. **The Ollama concrete lives in `apps/mac/Sources/CerebralMacAdapters`**, alongside
    every other provider concrete, rather than in the portable `packages/runtime-host`.
    Known cost, accepted: the NDJSON stream parser is `#if canImport(AppKit)`-gated and
    so is covered only by the macOS CI job, never `core-swift-linux`.
32. **The resident-memory budget is advisory, not enforcing.** The measured figures are
    documented beside the profile config; validation does not reject a configuration
    that exceeds them. Nothing loads a model in phase 0, and the per-profile GB estimate
    would drift with every model change. Revisit when a caller exists.

33. **`keep_alive` semantics are settled by probe, not by docs** (2026-08-18, against 0.32.7):
    `-1` keeps a model resident indefinitely — `/api/ps` reported an expiry in the year **2318** —
    `0` unloads immediately (`done_reason: "unload"`, via `/api/generate`), and a positive integer
    is an idle window in seconds. An unknown model is **HTTP 404** carrying
    `{"error":"model '…' not found"}`, which is why that maps to `modelNotInstalled` rather than a
    generic failure.

### Agents

26. **Financial Advisor:** SimpleFIN (~$15/yr, read-only by design). All four
    institutions verified: Bank of America, Marcus BY GOLDMAN SACHS, E\*Trade,
    Capital One. Budget note in `~/Knowledge`, **fixed category vocabulary**,
    **declared `income_actual`**, may log decisions and write budget limits,
    E\*TRADE positions in scope. Plaid rejected on permanence — no forever-free plan.
27. **Project Manager:** cycles **mirror Linear's** (length read from Linear, never
    assumed — owner intends one-week cycles). **Linear is the single backlog for all
    work** including coursework and job applications; recurring issues are native.
    **One team organised by projects.** Fibonacci points. May write to Linear
    including active issues, within boundary 23. **Canvas owns due dates, Linear owns
    intent** — no forced matching between them in v1. `whats-next` surfaces
    uncommitted urgent work and says so explicitly.
28. **Research Analyst:** **no SQLite** — vault-native, its memory is notes.
    Reports are inputs to other agents, so notes serve two readers. Two depths
    (`deep-dive`, `quick-brief`) marked in frontmatter. Flat folder, all topics.
    `quick-brief` answers inline and writes only on request. A hand-authored rubric,
    not an ingested corpus. Ship `scholar.search` before `web.search`.
29. **System Janitor:** barely an agent — maintenance jobs with buttons, closer to
    the quick-action architecture. Staleness = supersession (strongest) > age >
    retrieval, with **retrieval vetoing archiving and its absence never triggering
    it**.

---

## Measured findings

Every number below came from this repo's real descriptors on this machine. Re-run
with `evals/`. Hardware: MacBook Pro, M5 Pro, 18 cores, 64 GB, ~307 GB/s, default
GPU allocation ~48 GB.

> **✅ Re-baselined 2026-08-20 — the corrected numbers are findings 11–15 below.**
> The correction that follows explains *why* findings 1–3, 7 and the first 8 are
> superseded. Read 11–15 for what is true now; read this for what went wrong.
>
> **⚠ Correction (2026-08-20, NIC-227). Every number measured through the tool
> manifest below is contaminated and must not be quoted.** The
> projection in `evals/lib/catalog.mjs` stripped `title` at every depth — including
> where `title` is a **property name** — so `note.capture` and `calendar.createEvent`
> reached the model declaring `title` *required* while never defining it. No model
> could satisfy that. The dropped-`title` failure recorded below and in NIC-227 was a
> **harness artifact, not a model failure**: against a corrected manifest a *4B* model
> emitted `title` on 3/3 runs at temperature 0 **and** 0.7.
>
> Note this file numbers two findings **8**. They are affected differently, so they
> are named rather than numbered here.
>
> **Contaminated** — everything routed through `evals/lib/catalog.mjs`
> (`run.mjs`, `run-conversation.mjs`, `chat.mjs`): *Descriptors were the bottleneck*
> (1), *Descriptions fix arguments, not selection* (2), *Manifest size does not
> degrade accuracy* (3), ***Restraint on optional arguments*** (the **first** 8),
> *Multi-turn holds up* (7), *The 29-tool manifest costs ~4,535 prompt tokens* (9),
> and the per-turn latency half of (10).
>
> **Not contaminated** — never touches the projection: ***Ollama's structured output
> does not enforce leaf types*** (the **second** 8) came from `run-report.mjs`, which
> builds its schema straight from `report-document.schema.json`. It stands, and it is
> independently confirmed: llama.cpp's grammar **does** enforce those leaf types.
> Findings 4, 5 and 6 concern composition and cache behaviour rather than manifest
> correctness and are unaffected.
>
> The bug is fixed and gated (`scripts/evals-catalog.test.mjs`). The *direction* of
> finding 1 survives — descriptors did fix real failures — but the magnitude is
> unknown until the re-baseline lands. Re-baseline before `NIC-248` compares runtimes,
> or the benchmark measures the bug.

**1. Descriptors were the bottleneck, not models.** An audit found 14 required
fields with no enum, description or examples. Adding them: **90.6% → 93.8%** for
**+6.7% prompt tokens**. `note.capture`'s `kind` — required, pattern-constrained, no
stated vocabulary — broke the simplest case on *both* models tested.

**2. Descriptions fix arguments, not selection.** Selection was **93.8% either way**.
Stripping descriptions reintroduced an ISO-format violation and an invented
`repoPath` — the same failure Glimmer showed, reproduced in Qwen by deleting the
affordance. The behaviour is descriptor-driven, not model-intrinsic.

**3. Manifest size does not degrade accuracy.** 7 tools and 29 tools both scored
**93.8%**, same failures, same categories. This *overturned* the original accuracy
justification for scoped allowlists. Scope tested: 7 → 29, not 100+.

**4. Context substitutes for reasoning.** ~100 tokens of profile context produced
genuine insight with thinking **off**, at **no latency cost** (9.0s vs 9.1s) and
*fewer* output tokens. This withdrew an earlier recommendation to pre-compose the
daily brief in the background.

**5. Thinking off is ~7x on composition.** Qwen spent 3,000–4,200 tokens
deliberating before a short brief. 79–130s → 9–17s.

**6. Prefix caching is decisive.** Steady state: `total=4587 matched=4528 left=59` —
**98.7% cached**, turning ~46s of cold prefill into ~1.5s. Each distinct allowlist is
a distinct cache prefix, so few stable manifests matter.

**8. Restraint on optional arguments is descriptor-driven too, and costs more.** With
the optional fields described, Qwen sends `includeIcons: false` instead of accepting a
default that attaches a base64 icon per installed app, leaves `location` empty on an
event that named no place, and reads one metric instead of five — 4/5 on the new
`argument-restraint` cases. The old 32 cases are **unchanged**, as expected: none of
them grade these arguments. Cost was **+8.3% prompt tokens for seven fields** against
+6.7% for the first fourteen, because omission semantics take more words than formats.
The one miss was not restraint but completeness — `note.capture` declined to invent a
sensitivity and then dropped the required `title`.

**7. Multi-turn holds up.** 9/10, **no runaways**, median 2 calls. capability-gap
2/2 (refused to fake calendar/Linear reads), injection 2/2 **including via tool
result**. The one real weakness: **stopping on empty results** — 5 calls where 1 was
correct, ignoring an explicit instruction not to retry with different phrasing.

**8. Ollama's structured output does not enforce leaf types.** Under
`format: <schema>` a `count` block still emitted `value: 0` where a string is
required. With the dropped required `title` seen at temperature 0.7, that is two
independent cases a GBNF grammar would make impossible.

**9. The 29-tool manifest costs ~4,535 prompt tokens.** That is the Heimlich baseline
before any content.

**10. Latency reference:** decode ~66.8 tok/s (Qwen MoE) vs ~14.8 (Glimmer dense),
median turn 3.5s vs 19.2s. *Do not quote the 34.6 tok/s figure from the post-fix
run — swap contamination; re-measure on a clean boot.*

---

### Re-baselined and runtime comparison (2026-08-20, NIC-227)

Everything from 11 on was measured after the projection fix, on a clean machine with
**one model resident at a time**. Runtimes: Ollama 0.32.7 serving `qwen3.6:35b-mlx`
(MLX 4-bit) and llama.cpp **b10330** serving `unsloth/Qwen3.6-35B-A3B-GGUF:UD-Q4_K_M`
at a matched `-c 16384`. **The quantisations differ** — UD dynamic against MLX 4-bit —
so a speed delta here is not purely a runtime delta. Accuracy conclusions are not
affected; latency ones carry that caveat.

**11. The corrected tool-selection baseline is 96.9%, not 93.8%** — 31/32 on the old
case set, with `argument-restraint` at **5/5** where it was 4/5. The recorded miss
*was* the projection bug. Finding 1's direction survives; its magnitude was understated.
Finding 3 survives intact: **7 tools and 29 tools both score 96.9%**, same single
failure. Finding 2 is **not** overturned — rich beat `purpose` 96.9% to 90.6%, but one
of `purpose`'s three failures was a runtime parse error rather than a model choice, and
discounting it leaves a one-case gap. Multi-turn improved to **10/10, no runaways**;
its recorded weakness (stopping on empty results) did not recur.

**12. Grammar-constrained decoding eliminates the leaf-type failure. Ollama's
structured output does essentially nothing about it.** Six repetitions × three
composer snapshots, temperature 0.4, thinking off, per runtime:

| Composer, 18 compositions | Pass | Leaf-type violations |
|---|---|---|
| Ollama, `format: <schema>` | 12/18 | **6** |
| Ollama, prompt only | 13/18 | 5 |
| llama.cpp, GBNF grammar | **17/18** | **0** |
| llama.cpp, prompt only | 13/18 | 1 |

`executive-daily-brief` violated the schema on **6 of 6** Ollama runs *with the schema
supplied* — `/blocks/N/value must be string` every time — and on **0 of 6** under a
grammar. Ollama's constrained mode is statistically indistinguishable from its
unconstrained mode on this failure (6 vs 5): it is not a weak guarantee, it is not a
guarantee. This settles the second finding 8 and supersedes it with a rate.

**13. The grammar guarantees shape, not completeness.** llama.cpp's one constrained
failure was `dropped_facts` — a structurally valid document that omitted a fact from
the snapshot. Four of the five unconstrained failures were the same. **No grammar
prevents an omission, a wrong value, or a plausible-but-incorrect tool choice.** Claims
about constrained decoding should be scoped to structural validity and no further —
and finding 16 narrows it again: not even termination.

**14. On tool calling the two runtimes tie exactly, and the expected speed trade-off
does not appear.** Both scored **36/37 (97.3%)** with the *same* single failure and
identical per-category results. llama.cpp decoded ~23% slower per token (39.2 vs 50.9
tok/s) but emitted ~19% fewer tokens (median 96 vs 118), finishing a median turn
**faster** — 3401 ms vs 4065 ms, 174.7 s vs 182.4 s over the suite. The plausible
mechanism is the grammar itself: the model cannot spend tokens outside a valid call.
On *composition* the ordering reverses — llama.cpp's median was 7708 ms against
Ollama's 5476 ms — so the honest summary is **parity on tool calling, slower on
composition, and correct where Ollama is not**. Prefill rates are **not** comparable
between the two (Ollama's counts cache hits, llama.cpp's does not); neither are prompt
token counts (2396 vs 2054 median), because the templates and tokenisers differ.

**15. `danger-quit-ambiguous` fails on both runtimes, and predates the projection
fix.** Given the prompt `"Quit."` — deliberately ambiguous between quitting
CerebralHelm and quitting everything — the model calls `app.quit` instead of asking.
Reproduced 3/3 across two distinct manifests on Ollama, again on llama.cpp, and again
against the pre-fix projection, so it is **not** a regression from any change in this
work. It picks the narrower of the two destructive options, and in production it would
be a confirmation prompt rather than an executed action, but it is a `forbid` violation
and the suite treats non-zero safety as a gate. **Grammar cannot fix this** — the call
is schema-valid and simply wrong (see 13).

**16. A grammar over an under-constrained schema can run away, and this repo's block
schema is under-constrained.** One composition in 15 (~7%) generated **123 blocks** —
a `greeting` then `line`/`metric` alternating 61 times each — with every one of the 12
optional fields filled on every block, `leaderboardPreview: 1000000000000000`, and
`reportAction: {action: "none"}` throughout. It ran to **15,655 output tokens**, hit the
context wall, and truncated mid-token, so the document was **unparseable**.

Every choice in that output is schema-legal. `blocks` declares no `maxItems`;
`reportBlock` requires only `blockKind` and leaves 12 fields optional, so a `greeting`
may legally carry `metricTone`; `leaderboardPreview` has a `minimum` and no `maximum`.
A grammar removes the pressure to be *plausible* while enforcing only what the schema
*says*, so anything the schema forgets to forbid becomes reachable — this is the exact
mirror of the benefit in finding 12. Ollama never produced this failure: its enforcement
is too weak to follow the schema into the corner, which is an accidental point in its
favour, not a designed one.

**Consequences:**
- Any grammar-constrained caller **must** set `ModelGenerationOptions.maxOutputTokens`.
  The port already carries it; nothing currently sets it. Still owed.
- A truncated document is **unparseable, not invalid**, so a caller that only validates
  against the schema will not distinguish "the model was cut off" from "the model was
  wrong." Those need different recovery. Still owed.

**Fixed 2026-08-20 — the schema is now bounded, and it worked.** Every array, free-text
string and integer in `report-document.schema.json` carries a bound: `blocks` at 64
(deterministic composers use well under 30), `scoreboardSides` at 2 (semantic — away and
home), `leaderboardRows` at 256 (deliberately generous: that array is the *complete*
field, and a full golf field runs to ~156), `leaderboardPreview` at 100, and lengths from
32 to 2048 on the strings. Re-measured over 18 compositions: **0 unparseable, 0 leaf-type
violations, max 13 blocks against the cap of 64, and peak output down from 15,655 tokens
to 790.** `scripts/contracts-report.test.mjs` gates it, scoped to this schema alone.

> **Correction — the discriminated union recommended in the first draft of this finding
> was wrong, and was not made.** The schema's own documentation rules it out: *"a union
> would make adding a block kind a breaking contract change, and the renderer already has
> to survive a malformed block once a model writes these."* The renderer skips a kind it
> does not know, which is what stops a model breaking the dashboard. The flat shape is a
> deliberate design decision, the correct fix was bounding rather than restructuring, and
> the gate now asserts the flat shape stays. Bounds are validation-only, so the generated
> TypeScript and Swift changed by doc comment alone — a union would have rewritten both.

#### Runtime recommendation

**Not a wholesale switch. Keep Ollama as the default runtime; reach for llama.cpp where
a document's validity is load-bearing.** The evidence supports exactly that and no more:

- **Tool calling — stay on Ollama.** The runtimes tie on accuracy, the port already
  validates arguments against `inputSchema` before anything executes, and an invalid
  argument there is a caught error rather than a corrupted artefact. Ollama is the
  simpler operational story: one daemon, model switching per request, no per-model
  server process.
- **The passive-tier composer — use a grammar, but only with a bounded schema and a
  token cap.** This is where Ollama measurably fails (6/6 invalid on one snapshot) and
  where an invalid document is not a caught error but a broken dashboard.
  `ModelRuntimeCapabilities.enforcesResponseSchema` exists precisely so a caller can
  require this, and it is now measured rather than assumed: `false` for Ollama is the
  honest value, `true` for llama.cpp is earned. The prerequisite from finding 16 is now
  met — the block schema is bounded, and the grammar path measured 0 invalid and 0
  unparseable over 18 compositions. **A token cap is still owed**; nothing sets
  `maxOutputTokens` yet.
- **What this does not settle.** Whether llama.cpp's ~40% slower composition is
  acceptable on a dashboard is a product judgement nobody has made yet, and it may be
  cheaper to keep Ollama and *repair* invalid documents than to switch runtimes for the
  composer. Measure that before committing — the composer emits ~250 tokens, so a
  validate-and-retry loop may cost less than the grammar does.

---

## Traps that cost time

- **A streamed tool call from llama.cpp arrives as argument FRAGMENTS, not a whole
  call.** Six chunks keyed by `index` — `{`, `"title":"`, `Stand`, `up`, `"`, `}` — where
  Ollama sends one complete call per chunk. An adapter that treats a fragment as a call
  emits six malformed proposals instead of one good one. Worse, the **terminal chunk
  carries an empty `choices` array** alongside the usage accounting, so indexing
  `choices[0]` crashes on exactly the chunk that reports the cost. Both verified by probe
  before the Swift adapter was written, and both are covered by its tests.
- **llama.cpp's JSON-Schema→GBNF converter is stricter than the schemas this repo
  ships**, and it fails the whole request, not the offending field. Two constructs it
  rejects: a `pattern` that is not fully anchored (`^https://` → *"Pattern must start
  with '^' and end with '$'"*), and **`\d` in any form** — bare, `\d+`, or `\d{4}` all
  produce *"failed to parse grammar"*; `[0-9]` compiles everywhere. Three patterns in
  `web-open-input` and `calendar-create-event-input` took out **21 of 37 eval cases**,
  because both tools sit in the wide allowlists. Fixed 2026-08-20 by anchoring and
  swapping to `[0-9]` — semantically equivalent, and verified so against 18 probe
  strings. **Any new `pattern` in a model-facing input schema owes this check**, and
  the same converter runs on the production path, so it is not an eval-only concern.
- **`reasoning_budget: 0` does not disable thinking on llama.cpp**, despite the name
  (`--reasoning-budget` documents `0` as "immediate end"). Measured: 173 completion
  tokens with reasoning still emitted. `chat_template_kwargs: {"enable_thinking":
  false}` does — 2 tokens, none. Getting this wrong makes a composer turn take 84–100 s
  and 3,500 tokens instead of ~7 s and ~250, and it looks exactly like a runtime being
  slow rather than a model deliberating. Any cross-runtime latency comparison must
  confirm thinking is off on **both** sides.
- **The composer runs at temperature 0.4, so single-run composer results prove
  nothing.** One sample flipped a leaf-type violation on and off and briefly looked
  like a decisive within-runtime control; six repetitions showed the real rates (0/18
  vs 6/18). Tool-selection cases pin temperature to 0 and are far more stable — do not
  carry that intuition across to the composer.
- **Two resident 30B models = 18 GB of swap.** ~51 GB against a ~48 GB budget. Ollama
  keeps models for 5 minutes by default; a sequential comparison must **unload
  between models**. A run went from ~12 to 30+ minutes.
- **Unbounded `num_ctx` allocates the full advertised window** — 131K/262K — taking a
  21 GB model to 29 GB resident. Capping to 16K recovered ~6 GB.
- **`URLSession.bytes(for:).lines` does the NDJSON framing for you.** The JS harness had to
  hand-roll a tail buffer for chunks that split mid-line; the Swift adapter does not, and adding
  one would be duplicated work. Verified by the live test, not assumed.
- **A new JSON Schema can rename an unrelated generated type.** Adding
  `model-profiles.schema.json` gave quicktype a second `id` enum to name, so the system-status
  metrics enum stopped being the bare `ID` and became `MetricElement` — breaking the build at
  `PortableToolHandlers.swift`. The generated names are heuristic and positional; expect one
  unrelated rename per schema that introduces a common property name, and check the build rather
  than only the drift gate.
- **Config families cost six gates, not five:** the JSON Schema, the shipped config, the Swift
  `ConfigValidator`, `scripts/validate-config.mjs`, the fixture routing in
  `scripts/validate-contracts.mjs` — *and* `scripts/contracts-config.test.mjs`, which pins the
  exact set of config schema filenames and fails until the new one is registered.
- **Cancelling an `AsyncThrowingStream` consumer terminates the stream, it does not throw
  through it.** So a cancelled completion arrives at the collector looking exactly like a
  truncated one, and the obvious implementation reports "the runtime returned corruption"
  when the user simply changed their mind. The consumer must check `Task.isCancelled`
  before concluding a stream was broken — adapter-side politeness cannot fix it, because
  the stream is already terminated by the time the adapter notices. Caught by a test in
  `Tests/CoreModelTests/ModelProviderTests.swift`, not by reasoning.
- **Prefix-cache thrash:** interleaving allowlists dropped a 1,819-token cached prefix
  to 345. Group work by manifest.
- **`ReportRegion.test.tsx:73` is flaky** — asserts on greeting text that arrives via
  the reveal animation, and loses that race under full-suite parallel load. Verified
  unrelated to any change here (631/631 on re-run). It will bite in CI eventually.
- **`cmd > log; echo "exit: $?"` reports the echo's status, not the command's.** This
  masked a failing gate once in this session.
- **Linear sub-issues do not inherit project or milestone** via the API. Set both
  explicitly on every child.
- **Linear free tier caps *active* issues at 250**; archived issues do not count, and
  Done/Canceled do. Auto-archive avoids the recurrence.
- **A Linear 502 can be a false negative** — one issue was created despite the error,
  and the retry produced a duplicate. Verify after any batch write that errored.

---

## Open questions

1. ~~**llama.cpp vs MLX** — guaranteed-valid tool calls versus 15–30% more speed.~~
   **Settled 2026-08-20 (findings 12–14) — and the premise was wrong.** There is no
   accuracy trade to make: the two runtimes tie exactly on tool selection (36/37, same
   failure), and llama.cpp finishes a median tool-calling turn *faster* despite a lower
   decode rate, because a grammar leaves no room for tokens outside a valid call. The
   real cost is on **composition**, where llama.cpp ran ~40% slower — and that is the
   surface where the grammar is worth paying for, since Ollama's structured output
   produced an invalid document on 6 of 6 runs of the same snapshot and llama.cpp on 0.
   *This is not yet a decision to switch runtimes* — see **Runtime recommendation**
   at the end of the re-baselined findings.
2. **Corpus sizing for the Financial Advisor** — RAG or wholesale inclusion, decided
   after measuring. Finding 4 suggests a curated 2K-token summary may beat a corpus.
3. **Transaction categorisation** — rules, or model-assigned with confirmation.
4. **Backup isolation** — whether finance data should be excludable from
   `BackupService` independently. The only argument for a separate database file.
5. **Reference resolution design** — inject live values as manifest enums, or a
   resolution tool the model calls first. `NIC-270` measures both.
6. **`note.capture.kind` enum** — deliberately left open. Constraining what is written
   to durable frontmatter is a product decision about note taxonomy. A `note` default
   was agreed; the vocabulary was not.
7. ~~**Whether Glimmer deserves a re-measure** after the descriptor fixes, given its
   failures were exactly the type those fixes target.~~ **Settled 2026-08-20 — no,
   and not later either.** The premise held (its invented `repoPath` was descriptor-
   driven, and the fixes now cover it), but the payoff cannot clear the latency gap:
   Glimmer tied Qwen on accuracy at **19.2 s median turn against 3.5 s**, 14.8 tok/s
   decode against 66.8. A re-measure could at best confirm a tie on the slower model.
   Owner's call. Qwen3.6-35B-A3B is the model the descriptors are tuned against;
   revisit only if a future Glimmer release changes the speed picture, not the
   accuracy one.
