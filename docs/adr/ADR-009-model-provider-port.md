# ADR-009: Provider-neutral model port in core, with runtime abstraction and owned model lifecycle

- Status: Accepted
- Date: 2026-08-18

## Context

CerebralHelm has shipped and is in daily use with no model attached. Every AI phase in
[`docs/llm-integration/PLAN.md`](../llm-integration/PLAN.md) — the passive composer, the generic
tool-invocation path, retrieval, the four scoped agents, and Heimlich — sits downstream of one
missing primitive: a way for the runtime to ask a model for a completion. Phase 0 builds that
primitive alone, with no caller, so the shape is settled before four surfaces depend on it.

The MVP PRD locks that no model is required for the product to work: deterministic commands,
quick actions, mode application, note capture, note search, observability, and updates must all
function offline with no AI provider present. That constraint does not relax here — it is the
reason the port is additive and unbound.

The tech stack locks the surrounding boundaries:

- `packages/` must compile on non-Mac environments and must not import AppKit;
- platform, provider, model, and storage behaviour lives behind replaceable adapters at
  application edges;
- exact model IDs are resolved from versioned configuration, and no named local model may become
  an architectural dependency;
- product logic addresses capability profiles — `fast`, `balanced`, `deep`, `local` — rather than
  model names.

Three findings from the 2026-08-11 benchmarking session (recorded in full in
[`docs/llm-integration/README.md`](../llm-integration/README.md)) bear directly on this decision.

**The runtime, not just the model, is the swappable part.** llama.cpp ships integrated GBNF
grammar compilation that masks invalid tokens at every sampling step. MLX has no core equivalent;
constrained decoding is a bolt-on. MLX runs 15–30% faster and roughly 10% leaner on Apple Silicon.
That is guaranteed-valid tool calls versus speed, and it is unresolved — it is settled by
measurement in NIC-227. Independently, Ollama's `format: <schema>` was observed **not** to enforce
leaf types: a `count` block emitted `value: 0` where a string was required. A port that abstracts
only "which model" cannot express that difference; a port that abstracts the runtime can.

**Model lifecycle is a memory decision, and an expensive one to get wrong.** Two resident 30B
models measured ~51 GB against a ~48 GB default GPU allocation, driving 18 GB of swap and taking a
benchmark run from ~12 minutes to over 30. Ollama's default `keep_alive` evicts after five
minutes, and a cold reload cost ~70 s — so an always-on surface must pin and a rare specialist must
not. Left unbounded, `num_ctx` allocates the model's full advertised window (131K/262K), taking a
21 GB model to 29 GB resident; capping to 16K recovered ~6 GB. Residency and context sizing are
therefore not adapter trivia, and they are not per-call arguments a caller should be inventing.

**The landscape churns on three axes.** Tool-call format (each model family parses its own),
context length, and modality — text-only today, vision needed for the North Star screen-context
feature. Everything else may be assumed stable.

## Decision

Define one provider-neutral model port in `packages/core`, and make it the single seam through
which any model is reached.

The port will:

- expose streaming, cancellation, timeout, and token accounting as first-class contract elements,
  not adapter conveniences;
- name **runtimes**, not only models, and let a caller query runtime capabilities — tool-call
  support, thinking toggle, grammar-constrained decoding, vision, maximum context — rather than
  assume them;
- normalise tool calls into one typed shape, so a model family's wire format never reaches a
  caller;
- carry a response-format seam that expresses `text` and `jsonSchema` today and admits
  grammar-constrained decoding later (NIC-249) without a caller-visible change;
- report usage per response — prompt and output tokens, prefill and decode rates, wall duration.

Concrete providers live at the application layer. The first is an Ollama adapter in
`apps/mac/Sources/CerebralMacAdapters`, alongside every other provider concrete in the product.

**Model lifecycle belongs to the port's configuration, not to callers.** Versioned configuration
resolves a capability profile to its model id, runtime id, context-token cap, residency directive
(pinned, session-bounded, or evict-after-use), and thinking flag. A caller asks for `balanced`; it
does not choose a model, a context size, or a residency.

**Product logic addresses capability profiles.** `fast`, `balanced`, `deep`, and `local` are the
configuration keys, per the tech stack. In a local-first system every profile is served locally
today; `local` is reserved for surfaces that must never leave the machine even if a cloud escape
hatch is later enabled, which makes it a policy statement rather than a redundant one.

The measured resident-memory figures are documented alongside the profile configuration, but the
budget is **advisory**: configuration validation records it and does not reject a configuration
that exceeds it. Nothing loads a model in this phase, and the estimate would drift with every
model change.

**Local-first stands.** Every profile resolves to a local runtime by default. A cloud provider may
later implement the same port, but it stays off by default and confirmation-gated when it exists.
No cloud concrete is built here.

Nothing calls the port in this phase. It is verified by unit tests over the protocol and the
adapter's pure helpers, plus an opt-in live check against a local runtime.

## Alternatives considered

### A model-only port, with the runtime chosen inside each adapter

Rejected because it cannot express the one difference that matters most. Whether invalid tool
arguments are impossible (llama.cpp grammars) or merely unlikely (Ollama's non-enforcing
structured output) is a property of the runtime, and callers must be able to learn it and degrade
honestly. Burying it in an adapter turns an open, measurable question into a silent assumption.

### Lifecycle as per-call arguments

Rejected because it distributes a memory decision across every call site. Residency and context
sizing were measured as the difference between a system that fits and one that swaps 18 GB, and
per-call arguments guarantee that some future caller passes the wrong one. Configuration also
satisfies the standing rule that exact model IDs are resolved from versioned config and that no
named local model becomes an architectural dependency.

### Model names in product logic rather than capability profiles

Rejected by the tech stack, and rightly: the default model changed once during planning already
(`qwen3.6:35b-mlx` over `muse-glimmer:30b-mlx`, tied on accuracy and ~4.5x faster on decode), and
the landscape moved substantially in the three months before the plan was written. Profiles
survive that churn; model names do not.

### The concrete adapter in `packages/runtime-host`

Rejected. It is portable app-layer composition, and placing the Ollama client there would give the
streaming parser coverage in the Linux CI job. But it puts a provider concrete inside `packages/`,
against the boundary rule that provider and model implementations remain adapters at application
edges, and it would split the provider family across two homes for one adapter's benefit.

### Enforcing the resident-memory budget in configuration validation

Rejected for this phase. Enforcement requires every profile to declare an estimated resident
footprint that drifts as models and quantisations change, and nothing in phase 0 loads a model, so
the guard would police a situation that cannot yet occur. Revisit when a caller exists.

### A TypeScript agent sidecar as the first integration

Rejected as the starting point. The tech stack recommends a sidecar for the eventual agent
service, but phase 0's purpose is the primitive underneath it. Introducing a second process,
runtime, and packaging story before a single completion has been streamed would put the hardest
operational surface first and teach the least.

## Consequences

### Positive

- The llama.cpp-versus-MLX question can be answered with measurements later without a caller-visible
  change, because runtime identity and runtime capabilities are already in the contract.
- Residency and context sizing become reviewable configuration with measured defaults, rather than
  constants rediscovered in an adapter after a machine starts swapping.
- Callers address stable capability profiles, so replacing the default model is a configuration
  edit rather than a code change.
- Token accounting arrives with the first completion, so latency and cost are observable from the
  first surface that uses it rather than retrofitted.
- The product's offline guarantee is untouched: the port is additive, unbound, and absent from
  every deterministic path.

### Negative

- The adapter is `#if canImport(AppKit)`-gated like its siblings, so the newline-delimited-JSON
  stream parser — the subtlest new code in the phase — is exercised only by the macOS CI job, not
  the Linux one.
- A capability profile is one level of indirection between a surface and the model that serves it.
  Diagnosing "why was this answer poor" means reading configuration first.
- The advisory budget documents the 18 GB-swap trap without preventing it. A hand-edited
  configuration can still pin more than the machine holds.
- Configuration gains a family, which must be kept in step across the JSON Schema, the generated
  TypeScript and Swift bindings, and both the Swift and Node validators.

### Follow-on implications

- Grammar-constrained decoding (NIC-227, NIC-249) fills the response-format seam this ADR
  establishes; descriptors stay authoritative under ADR-003 and grammars are derived from
  `inputSchema`, never hand-maintained.
- The embedding model is a separate port (NIC-271) with its own residency story — always-resident
  and small — and is deliberately not a capability profile.
- Risk classification and confirmation policy remain outside the model and outside this port
  (ADR-003). This port produces text, tool-call proposals, and usage; it authorises nothing.
- If a cloud provider is ever added, it implements this port, stays off by default, and is
  confirmation-gated. It does not get a parallel path.
- Phase 1's composer is the first caller, and the first real test of whether profiles, context caps,
  and residency were drawn in the right places.
