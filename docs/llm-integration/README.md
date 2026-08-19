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

- **Phase 0 is underway.** `NIC-225`: ADR-009 is written and the `ModelProvider` port
  exists in `packages/core/Sources/CerebralCore/Model/` (`NIC-241`, 2026-08-18) — protocol,
  request/usage types, `ModelDeadline`, `MockModelProvider`. The profile catalog is configuration
  (`NIC-243`): `config/models/profiles.json` + `model-profiles.schema.json`, resolved by
  `ModelProfileCatalog`, optional everywhere. The Ollama adapter (`NIC-242`) is built at
  `apps/mac/Sources/CerebralMacAdapters/OllamaModelProvider.swift` and **verified against a live
  Ollama 0.32.7** — a streamed completion in 9.0 s with real token accounting, plus 18 offline
  helper tests. Nothing calls any of it, by design: phase 0 is complete and the first caller is
  `NIC-250`. Everything else in the milestone remains Backlog.
- **Committed:** descriptor affordances on `fix/tool-descriptor-model-affordances`;
  plan, charters and eval harness on `feat/llm-eval-harness`. Both pushed, both
  awaiting merge to `dev`. Full `node scripts/test.mjs` green on the contract change.
- **Installed locally:** Ollama 0.32.7, llama.cpp (Homebrew), and ~42 GB of models —
  `muse-glimmer:30b-mlx`, `qwen3.6:35b-mlx`, `qwen3-embedding:0.6b`.

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

## Traps that cost time

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

1. **llama.cpp vs MLX** — guaranteed-valid tool calls versus 15–30% more speed.
   Settled by `NIC-247`/`NIC-248`.
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
7. **Whether Glimmer deserves a re-measure** after the descriptor fixes, given its
   failures were exactly the type those fixes target.
