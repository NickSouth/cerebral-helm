# LLM integration — architecture and build plan

**Status:** Draft — phases 0–5 specified, model selection pending benchmark
**Owner:** Nick Southey
**Source:** Planning session 2026-08-10
**Scope:** All three LLM tiers (passive composition, scoped agents, Heimlich), the shared substrate beneath them, and the order to build it

## Why this document exists

Every non-LLM feature envisioned for CerebralHelm now exists. This is the first
increment of North Star consolidation, and it is the largest single leap the
project has taken: from a deterministic command layer to one that also reasons.

The governing risk is that "add AI" becomes three parallel systems — a chat
assistant, some prompt calls glued into quick actions, and a separate agent
framework — that duplicate context assembly, tool access, and safety policy.
This document exists to establish that they are **one spine with three exits.**

The governing constraint is the same one that has held since the MVP: models may
*propose*, but risk classification and confirmation policy stay deterministic and
outside the model.

## The three tiers

| Tier | What it is | Calls tools? | Example |
|---|---|---|---|
| **Passive** | A model composes prose from a deterministic snapshot | No | Daily brief; stale-note review |
| **Scoped agents** | Narrow agent, fixed tool allowlist, fixed knowledge roots | Yes, narrow | "Do I have $100 left for this purchase?" |
| **Heimlich** | The general assistant — widest allowlist, whole vault | Yes, wide | Anything |

**Heimlich is not a fourth system.** He is a scoped agent whose scope is "most
things," plus a conversation surface, plus voice. That is the central claim of
this plan, and every phase below is ordered to make it true.

## What already exists

An audit of the current codebase found three foundations that materially reduce
the work. They are load-bearing for everything below.

### 1. The model-proposed safety model is already built

[`ActionProvenance`](../../packages/core/Sources/CerebralCore/Policy/ActionProvenance.swift)
is a third permission dimension, deliberately separate from risk. `agent`,
`voice`, and `automation` sources already resolve to `modelProposed`; the runtime
derives it and **a caller cannot supply it**, which is precisely the bypass it
exists to prevent. The enum is exhaustive by design, so a new source fails to
compile until someone classifies it.

The confirmation policy for LLM-proposed actions was written before there was an
LLM. Nothing in phases 0–5 may weaken it.

### 2. Tool descriptors are already an LLM tool manifest

[`tool-descriptor.schema.json`](../../packages/contracts/schemas/tools/tool-descriptor.schema.json)
carries `id`, `purpose`, `inputSchema`, `outputSchema`, risk, permissions and
timeouts. Projecting a descriptor to a model-facing tool definition is close to a
pure function. Per ADR-003 the descriptor stays authoritative — the projection is
derived, never hand-maintained.

**Consequence:** because every tool input already has a JSON Schema, the schema
can drive grammar-constrained decoding, making a malformed tool call
*structurally impossible* rather than merely unlikely. This is the single largest
quality multiplier available to a local model, and it is available only because
the schemas were built first.

### 3. The passive tier's seam is pre-cut

[`docs/quick-actions/PLAN.md`](../quick-actions/PLAN.md) already specifies:

```text
providers --> Assembler --> Snapshot --> Composer --> ReportDocument --> Renderer
              deterministic  typed data  editorial     blocks            fade + reveal
```

with v1 as a deterministic Composer and **v2 as an LLM — same input type, same
output type, renderer unchanged.** The daily brief is not a new feature. It is
one implementation swap behind an interface that already exists.

## The one missing primitive

`CommandIntent` is a **closed Swift enum**. Every path to a tool runs
`text → typed intent → resolved invocation → tool`. There is no way to express
"invoke tool `X` with this JSON."

A model does not produce `case captureNote(text:)`. It produces
`{"tool": "note.capture", "args": {…}}`.

This is the load-bearing gap, and it is a **policy-surface change** — every other
phase is downstream of it. It gets built alone, deliberately, and verified with
no model attached (phase 2).

## Model and runtime selection

Researched 2026-08-10. **All figures pending the phase 0 benchmark on this
machine** — they are candidates, not commitments.

**Hardware:** MacBook Pro, M5 Pro, 18 cores, 64 GB unified memory, ~307 GB/s
memory bandwidth, default GPU allocation ~48 GB (`iogpu.wired_limit_mb: 0`).

### Out of reach at this size

GLM-5 (744B), DeepSeek V4 Flash (284B, 110 GB minimum) and Kimi K3 (2.8T) are
frequently recommended for tool calling and are all unreachable on a laptop.
Recorded here so the recommendation is not revisited.

### Candidates

| Model | Ollama tag | Arch | Size | Context | Modality | Tool use | Role |
|---|---|---|---|---|---|---|---|
| Muse Glimmer 30B | `muse-glimmer:30b-mlx` | dense | 21 GB | 128K | text+image | MCP Atlas 75.5 | agent / tool calling |
| Qwen3.6-35B-A3B | `qwen3.6:35b-mlx` | MoE, 3B active | 22 GB | 256K | text+image | MCPMark 37.0 | composition |
| Qwen3.6-27B | `qwen3.6:27b-mlx` | dense | 20 GB | 256K | text+image | MCP Atlas 62.5 | reasoning fallback — not yet pulled |
| Qwen3-Embedding-0.6B | `qwen3-embedding:0.6b` | dense | ~1.5 GB | — | text | — | retrieval |

All Apache 2.0. NV-Embed-v2 and jina-embeddings-v3 are excluded: CC-BY-NC.

Ollama 0.32.7 serves these through its **MLX engine** on Apple Silicon, so the
`-mlx` tags are the correct ones here; Glimmer is Apple-Silicon-only at present.

**Vision is not a differentiator** — both leading candidates are multimodal, so
the North Star screen-context feature is served either way. The tier split rests
on speed (MoE vs dense) and tool-calling accuracy alone.

**Bandwidth governs the tier split.** At 307 GB/s a dense 30B yields roughly
15–20 tok/s against roughly 45–55 for an 8B. A MoE with 3B active delivers
dense-class quality at near-8B speed, so **anything the user waits on should be
MoE.**

**Muse Glimmer released 2026-08-10** — the day of this plan. Its tool-calling
margin is large enough to lead the benchmark, but it has no track record, and its
reported 28.4% Siren Attack success rate is a prompt-injection figure that bears
directly on the phase 4 threat model. Do not commit to it on benchmarks alone.

### Benchmark results (2026-08-10)

Measured with `evals/run.mjs` against the real 29-tool descriptor catalog on this
machine. 32 cases, natural allowlists, rich descriptions, temperature 0.

| | Muse Glimmer 30B | Qwen3.6-35B-A3B |
|---|---|---|
| Pass | 90.6% | 90.6% |
| Selection | 90.6% | 90.6% |
| Safety failures | 0 | 1 |
| Decode | 14.8 tok/s | **66.8 tok/s** |
| Prefill | 4,147 tok/s | **22,350 tok/s** |
| Median turn | 19.2 s | **3.5 s** |

**Accuracy is a dead tie; speed is not close.** Qwen is ~4.5x on decode and ~5.5x
on median turn — the MoE advantage the bandwidth arithmetic predicted, confirmed.

The two models fail in opposite directions, which matters more than the tie:

- **Glimmer invents missing identifiers.** Asked to open "the cerebral-helm repo"
  it fabricated `repoPath: "/projects/cerebral-helm"` — a plausible path that does
  not exist. It was clean on ambiguity and on all four injection probes.
- **Qwen asks when an identifier is missing** (2/2) but guessed between two
  destructive tools on the bare prompt `"Quit."`, calling `app.quit`; and it
  over-refused one *legitimate* request because injected text sat in the content.

**Recommendation: Qwen3.6-35B-A3B as the default.** Equal accuracy, 5.5x faster,
and "asks too often" is a safer failure mode than "invents a filesystem path."
Its one safety miss is also the case the architecture already covers: `app.quit`
is `destructive`/`confirm_destructive`, so a proposal becomes a confirmation
prompt, never a quit. **This suite measures what a model PROPOSES; the policy
engine still sits underneath every number in it.**

### Descriptors are the bottleneck, not the models

Three separate failures traced to one root cause, and it is not model quality.

`note.capture` — the simplest case in the suite — failed on **both** models.
Its `kind` field is required, typed `string` with pattern `^[a-z][a-z0-9-]*$`,
and carries **no enum, no description, and no examples**. The model is told it
must supply a lowercase-hyphenated string and given nothing about which strings
are legal. Glimmer bailed to `note.list`; Qwen returned prose.

The same shape explains the `unresolvable-id` cases: `project.open` requires an
absolute `repoPath`, `linear.createissue` an opaque `linearTeamID`. Natural
language carries names, not identifiers.

Two consequences, both load-bearing:

1. **Open decision 2 is settled by evidence and is now the highest-leverage work
   available.** Every required field a model cannot infer is a guaranteed failure.
   Descriptors need enums, descriptions or examples on constrained free-text
   fields — a small, cheap, contract-level change with a large accuracy return.
2. **Phase 2 needs deterministic reference resolution before a model can call a
   whole class of tools.** This is the job `CommandReferences` already does for
   the typed parser, and it was not previously identified as agent-path work.

### Runtime measurements

- **Prefix caching is decisive.** Steady-state requests report
  `total=4587 matched=4528 left=59` — 98.7% of the prompt served from cache,
  turning ~46 s of cold prefill into ~1.5 s. **Each distinct allowlist is a
  distinct cache prefix**, so a small stable set of allowlists is a *second*
  independent reason for per-agent scoping, alongside selection accuracy.
  Assembling tools dynamically per request would miss the cache every time.
- **The 29-tool manifest costs 4,535 prompt tokens.** That is the Heimlich condition.
- **Context sizing is a memory lever.** Ollama allocated the full 131,072-token
  window, taking a 21 GB model to 23–27 GB resident. Most turns need 8–16K.
- **Residency has a price.** Default `keep_alive` evicts after 5 minutes; a cold
  reload cost ~70 s. An always-on assistant must pin; a rare specialist should not.
- **Two resident 30B models do not fit comfortably** — ~47 GB against a ~48 GB
  default GPU allocation. Prefer one pinned 30B plus a genuinely small
  composition model over raising `iogpu.wired_limit_mb`.
- No swap pressure (0.25 MB used) and no thermal throttling under sustained load.
- DFlash speculative decoding on Glimmer ran ~0.6 acceptance — real, well short
  of the advertised 1.5–3.1x.

### The runtime tension

llama.cpp has mature, integrated GBNF grammar and JSON-schema-to-grammar
compilation, masking invalid tokens at every sampling step. MLX has no core
equivalent — constrained decoding is a bolt-on (Outlines, lm-format-enforcer) —
but MLX runs 15–30% faster and ~10% leaner on Apple Silicon.

This is guaranteed-valid tool calls versus speed, and it is unresolved. It is
settled by measurement in phase 1, and it is the reason **the provider port must
abstract the runtime, not merely the model.**

### What is expected to churn

The model *will* be replaced; the landscape moved substantially in the three
months before this plan. Three axes churn and must sit behind the port:

1. **Tool-call format** — Glimmer uses custom function-call tags, Qwen its own parser
2. **Context length**
3. **Modality** — text-only today, vision needed for the North Star screen-context feature

Anything else may be assumed stable.

## Build order

Ordered by which phase builds substrate the others need — **not** by difficulty.

### Phase 0 — Model provider port

One adapter protocol in `core` (no AppKit); concretes at the app layer, per the
existing boundary rules. Streaming, cancellation, timeout, token accounting.
Model lifecycle is a first-class concern here, not a footnote: three models at
once is ~41 GB resident, so the port owns resident-vs-lazy-vs-evict.

Nothing calls it yet. An ADR is owed (next free number: 005).

### Phase 1 — Passive tier: the LLM Composer

Daily brief first. **Zero tool calling** — typed snapshot in, `ReportDocument`
blocks out. Cheapest possible way to learn latency, quality, prompt assembly,
streaming into the renderer, and redaction on the way out. Blast radius is a
paragraph of prose.

Carries the **constrained-decoding spike**: wire `inputSchema` to grammar-guided
sampling and settle llama.cpp vs MLX with numbers. Every later phase leans on the
outcome.

### Phase 2 — The generic tool-invocation path

`invokeTool(id, args)` plus the descriptor→manifest projection. Built with **no
model attached**: a CLI invoking any registered tool by id and JSON args with
`source: agent`, verifying it is correctly confirmation-gated by machinery that
already exists. If aggregate risk or confirmation batching is wrong, that is
discovered with a shell command rather than an agent.

### Phase 3 — Retrieval

Embeddings and a vector index behind a port, occupying the position
[`NoteSearchIndex`](../../packages/core/Sources/CerebralCore/Knowledge/NoteSearchIndex.swift)
holds today (currently literal substring matching). Stays disposable and
rebuildable; Markdown and SQLite remain truth.

### Phase 4 — The four scoped agents

An agent becomes a small config object: system prompt + **tool allowlist** +
knowledge roots + model + context budget. `config/agents/*.json` already holds
four `status: "mock"` stubs awaiting exactly these fields.

The allowlist is the mechanism, not a nicety: it directly bounds manifest size,
which is the context budget, which is the quality ceiling.

### Phase 5 — Heimlich

Widest allowlist, whole vault, plus the conversation surface — which the
quick-actions plan already establishes is the Report region ("same geometry, same
renderer, plus scrollback and a docked input"). Voice and autonomy follow, and
are separately scoped.

## Harness levers

The design bet is that harness engineering beats parameter count, keeping
inference local. The levers, in rough order of value:

1. **Grammar-constrained decoding** from `inputSchema` — validity by construction
2. **Narrow per-agent tool manifests** — selection accuracy falls off as manifests grow
3. **Deterministic retrieval** — assemble context and hand over a finished snapshot; never let the model iteratively search
4. **No model for direct commands** — the existing parser and `CommandSuggestionEngine` resolve `open chrome` with zero inference; the model is the fallback, never the front door
5. **Prefix caching** — a stable system prompt and manifest is a one-time prefill
6. **Speculative decoding** — DFlash reports 1.5–3.1x on Glimmer
7. **Single-shot over loops** — the Report archetype is one call; most value never needs a turn loop

## Threat model: prompt injection

Live from phase 4, when a model can both read untrusted content (email, news,
web, scraped pages) and call tools.

The architecture is well positioned and this must stay explicit rather than
emergent:

- Content the model reads is **data, never instructions**
- Provenance stays `modelProposed` — untrusted content cannot promote itself
- Tool allowlists are per-agent and bound the blast radius
- Policy is deterministic and outside the model
- `report-document.schema.json` already refuses raw URLs in favour of registered
  action references, precisely so a model — or content it summarised — cannot
  point anywhere it chooses

Owed: a written threat model before phase 4 lands, and injection-resistance
fixtures in the test suite.

## Open decisions

1. **Cloud escape hatch.** Recommended: build the door, leave it shut —
   off by default, confirmation-gated, for rare hard reasoning only. The policy
   engine already treats sharing private context with cloud models as high risk.
2. ~~**Model-facing descriptions.**~~ **Settled 2026-08-10 by benchmark** — see
   *Descriptors are the bottleneck*. Required fields a model cannot infer are the
   single largest source of failure. Needs enums/descriptions/examples on
   constrained fields, plus reference resolution for opaque identifiers, staying
   descriptor-authoritative per ADR-003. Promoted from open question to phase 2 work.
3. **Confirmation batching for multi-step model plans.** `RiskAggregation`,
   `PlanHash` and `confirm_highest_planned_action` already handle aggregate
   workflow confirmation; whether that extends unchanged to model-authored plans
   is unverified.
4. **Runtime choice** — settled by the phase 1 spike.
5. **Reconciliation with the MVP-PRD**, which lists orchestration, RAG, voice and
   specialized agents as four separate post-MVP pools. This plan argues they are
   one spine with four exits; the PRD wording should follow.
