# ADR-007: Executive is the default mode

- Status: Accepted
- Date: 2026-06-30

## Context

CerebralHelm ships four modes — Executive, Developer, School, Entertainment — that
share one layout grammar and differ by theme, briefing, quick actions, apps, widgets,
and context (design spec §5.3, §6). The product needs a single, unambiguous **default
mode**: the mode the system boots into on first run and falls back to when no prior
mode is recorded (`FR-MOD`).

The authoritative source for this is already `config/defaults/app.json`
(`defaultModeId`), validated against an existing mode by the config gates
(`scripts/validate-config.mjs`, `ConfigValidator`). It is set to **`executive`**.

The repository nonetheless carried a stale **Developer** default in two places that
predated this config — historical artifacts of the earliest bootstrap work (the
canonical Developer fixture's project is literally "NIC-12 Workspace Bootstrap"):

- the dashboard mock seeded `mode.developer.ready` (`mockCerebralBridge.ts`);
- the canonical bridge bootstrap example (`bootstrap-state.json`) was Developer, and
  tests asserted `mode === "Developer"`.

So the configured default (Executive) and what the pre-Mac frontend actually booted
(Developer) disagreed. No specification ever stated Developer as the default; it was
an unreviewed fixture artifact.

## Decision

**Executive is the default mode, repository-wide.** `config/defaults/app.json`
`defaultModeId = "executive"` is the single source of truth; every other surface aligns
to it rather than hard-coding a default of its own.

- The dashboard's pre-Mac seed boots Executive (`DEFAULT_BOOTSTRAP_KEY = "mode.executive.ready"`).
- The canonical bridge bootstrap example (`bootstrap-state.json`) is an Executive state.
- The UI never hard-codes the default — it renders whatever mode the bootstrap state
  carries; the bridge resolves the default from config. Mode **persistence** (restoring
  the last valid mode) is separate and unchanged; Executive is the first-run value and
  the fallback when no prior mode exists.

Executive is the correct default because it is the **general command center** — the
broad "front door to the user's digital life" (design spec §6; product vision) — and is
the first control in the fixed mode switcher (§5.9). Developer is a specialized
workspace, not the general entry point.

## Alternatives considered

### Keep Developer as the boot mode

Rejected. Developer is a specialized engineering workspace; defaulting the general-purpose
product into it contradicts the "context-aware front door" goal. It was never a product
decision — only a leftover from the first bootstrap fixture — and it actively conflicted
with the already-configured `defaultModeId`.

### Add a second default-mode setting for the frontend

Rejected. A frontend-owned default duplicates `defaultModeId` and reintroduces exactly the
divergence this ADR resolves. The default lives in config; the UI consumes it.

### No default — always restore the last mode

Rejected as the *default* mechanism (it is the persistence mechanism, which already exists).
A first run, a reset, or an unreadable mode record still needs a deterministic fallback;
that fallback is the configured default = Executive.

## Consequences

### Positive

- One authoritative default (`config/defaults/app.json`), with the frontend seed,
  canonical fixture, and tests aligned — no more config-vs-frontend disagreement.
- The dashboard boots into the general command center, matching the product's framing.

### Negative

- The canonical bootstrap example and the dashboard's default story are now Executive;
  Developer-specific manual testing must select Developer explicitly (the mode switcher,
  NIC-54/D2, now performs the switch).

### Follow-on implications

- Future modes/config changes must keep `defaultModeId` pointing at a real mode (already
  gated). Any new "first-run mode" behavior reads from config, never a hard-coded literal.
- The original NIC-57 "Entertainment lighter density" direction is separately superseded
  (constant density across modes); unrelated to this ADR but part of the same mode-model
  cleanup.
