# CLAUDE.md

This file is auto-loaded into every session. It is a **router**, not a manual: it
orients you fast and points at the authoritative source for each thing. Read the
pointer, then read the source — do not assume the contents from here.

> `.agent/AGENTS.md` is the older long-form companion, last updated 2026-06-26. It
> predates the move to macOS: its "Windows Swift Verification" section describes a
> Windows/OneDrive machine that no longer exists, and it omits the JS/contract
> gates, the design-spec pointers, and the code map below. **This file wins.**
> Treat AGENTS.md as historical until someone reconciles it.

## What this is

CerebralHelm is a local-first agentic desktop environment for macOS, centered on
the assistant **Heimlich**: a persistent dashboard, command surface, mode engine,
knowledge system, and launcher for narrow tools and specialized agents. It is
**not** an OS replacement or an unrestricted chatbot. Goal: a reliable,
context-aware front door to the user's digital life. **Core principle: useful
before intelligent.**

**v1.0.0 shipped 2026-08-10** (`CHANGELOG.md`) and is in daily personal use. It is a
free-tier, personal-use app: signed with an Apple Development identity, never
notarized, installed by copying to `/Applications`. The deterministic foundation is
built — native AppKit + WKWebView shell, versioned bridge, mode engine, quick-action
workflows, window management, knowledge vault, and ~20 live widget integrations.
Voice, mobile, models, and agents must **extend the same contracts**, never fork
parallel systems.

Canonical vocabulary: Modes = Executive / Developer / School / Entertainment ·
Agent surfaces = Research Analyst / Financial Advisor / Project Manager / System
Janitor, **plus Heimlich himself as agent #5** — widest scope, a conversation
surface and voice, *not* a separate system · Durable knowledge = Markdown + SQLite ·
Vector indexes = disposable and rebuildable.

## Current frontier

> Keep this section current — it's the highest-value, fastest-stale pointer in the repo.

- **The MVP is closed.** ~139 issues Done, zero open. `.agent/spec/MVP-PRD.md` is now
  the record of what shipped and why, **not** a live scope gate. Don't reason about
  "MVP scope" as though it were pending work.
- **Two workstreams.** (1) Minor features and fixes on the shipped app — currently
  NIC-224 (report rendering), NIC-223 (news interests), NIC-221 (Linear projects
  widget). (2) **Local LLM integration** — the big one, see the next section.
- **Branch flow:** feature branch → PR → `dev` → `prod`, both current as of
  2026-08-18. No `v1.0.0` git tag was ever pushed, despite NIC-106 being closed.
- **Live trap:** every Playwright visual baseline is `-win32`, there is no Windows box
  and no Playwright CI job. The suite only *looks* green because it silently skips —
  see Verification before installing browsers.
- Resolved, no longer worth restating: the settings-read bridge op (`getSettings`)
  exists; the app has a stable signing identity, so the Accessibility TCC re-grant
  treadmill is gone; the mode-switch re-scope fully landed — no `enter-*` workflows
  remain, and `config/workflows/open-*-layout.json` are ordinary quick actions.

## LLM integration

**Nothing model-facing is built.** All 92 issues (NIC-225 → NIC-317, Linear milestone
*CerebralHelm Local LLMs*) are Backlog; 13 are pulled into the current cycle.

**Any work touching models, agents, retrieval, or evals reads
[`docs/llm-integration/README.md`](docs/llm-integration/README.md) first and keeps it
updated as it goes** — it is the decision log and index, and the place a session's
findings land so the next one never re-derives them.

- Why a decision was made · what was measured · traps · where to start → that README.
  It is *not* the architecture; PLAN.md and the charters win where they disagree.
- Architecture, the three tiers, phase order → [`PLAN.md`](docs/llm-integration/PLAN.md).
- One agent's persona, allowlist, state schema, protocols → [`agents/`](docs/llm-integration/agents/).
- Does a model still drive this repo's real tools → [`evals/README.md`](evals/README.md).

Invariants, before you open anything: three tiers, **one spine** — the passive tier
composes prose *and proposals* and executes nothing; agents read through tools, the
passive tier reads deterministically. **Models propose; risk classification and
confirmation policy stay deterministic, outside the model, and absent from the
model-facing manifest.** `ActionProvenance` may not be weakened. Agent memory is typed
domain state, never freeform model notes. Descriptors — not prompts — are the lever
for model accuracy, and every descriptor change owes an eval re-run.

*Unmerged:* that README exists only on the working branch, and the descriptor-affordance
commit (`ea666c1`, `fix/tool-descriptor-model-affordances`) is local-only and unpushed —
yet every post-fix benchmark number in PLAN.md depends on it. *Known doc conflict:*
README decision 20 (owner override — Heimlich MAY hold both `finance.*` and
`web.search`) contradicts PLAN.md's recommendation. **The owner's override wins**;
PLAN.md is owed the correction.

## Start here (orientation, cheapest first)

1. **The user's latest explicit instruction** — always outranks everything below.
2. **Live scope & acceptance criteria** → Linear (NIC-xx), plus `docs/llm-integration/`
   for the LLM programme.
3. **What shipped and why** → [`.agent/spec/MVP-PRD.md`](.agent/spec/MVP-PRD.md) —
   historical authority for MVP requirements, acceptance and release gates.
4. **Stack baseline & impl decisions** → [`.agent/spec/TECH-STACK.md`](.agent/spec/TECH-STACK.md).
   Only **Locked** rows bind; an ADR may override a **Recommended** one.
5. **UI/visual authority** → [`.agent/spec/CEREBRALHELM_DESIGN_SPEC.md`](.agent/spec/CEREBRALHELM_DESIGN_SPEC.md)
   + [`wiki/CerebralHelm-Visual-Design-Reference.pdf`](wiki/CerebralHelm-Visual-Design-Reference.pdf).
   **Precedence: the design spec beats the MVP-PRD for UI questions.** Day-to-day
   dashboard work reads the distilled [`.agent/spec/UI-CONSTITUTION.md`](.agent/spec/UI-CONSTITUTION.md)
   (tokens, grammar, per-increment checklist) — its rules and checklist bind; its header
   framing (the completed NIC-50 epic, "proposed" token values) is historical.
6. **Long-term intent** (future compatibility, not current scope) → [`wiki/NORTH-STAR.md`](wiki/NORTH-STAR.md).
7. **Hard architecture boundaries** → [`docs/architecture/repository-boundaries.md`](docs/architecture/repository-boundaries.md).
8. **Key decisions** → [`docs/adr/README.md`](docs/adr/) is the index; read it rather than
   any list here. ADR-001…008 exist: AppKit+WKWebView shell · single command lifecycle ·
   internal tool registry & risk policy · versioned bridge · vendored SQLite ·
   SQLite as sole operational-history source · Executive default mode · unsandboxed
   Developer ID distribution. **Next free number is 009.**
9. **Programme plans** — read only the one you're working in → [`docs/llm-integration/`](docs/llm-integration/)
   · [`docs/quick-actions/PLAN.md`](docs/quick-actions/PLAN.md) · [`docs/widget-work-handoff.md`](docs/widget-work-handoff.md)
   · `docs/mvp-polish/` · `docs/pre-ui-frontend/` (historical). Ops/release →
   `docs/operations/`, `docs/compatibility/`, `CHANGELOG.md`.

Renaming or deleting a spec/ADR requires updating [`docs/required-docs.json`](docs/required-docs.json) —
CI fails otherwise.

## Where the code lives

Root is both a SwiftPM package (`Package.swift`) and a pnpm workspace
(`pnpm-workspace.yaml` → `apps/*`, `packages/*`).

```
packages/           Portable Swift + language-neutral contracts. No AppKit — enforced by Tests/RepositoryBoundaryTests.
  contracts/        JSON Schemas: schemas/{commands,bridge,tools,config,knowledge,workflows,references,reports} + fixtures/.
                    GENERATED, never hand-edit: generated/typescript/contracts.ts and
                    Sources/CerebralContracts/GeneratedContracts.swift. Regenerate: node scripts/generate-contracts.mjs
  shared/ core/     CerebralShared (leaf utils) · CerebralCore (command runtime, policy/risk, tool registry, config, WorkspacePaths)
  bridge/           CerebralBridge — the versioned dashboard bridge contract (ADR-004)
  tools/ knowledge/ Siblings: both → core, never each other. Tool handlers · Markdown/YAML note vault
  storage/          CerebralStorage — SQLite via vendored swift-toolchain-sqlite (ADR-005)
  runtime-host/     Composes Core+Tools+Knowledge+Storage into the live runtime. THIS is where concretes compose.
apps/
  mac/              Native shell (ADR-001). Entry CerebralHelm/main.swift · adapters Sources/CerebralMacAdapters · CerebralHelm.xcodeproj
  dashboard/        React 19 + Vite. Entry src/main.tsx (?surface= selects dashboard/settings/moreapps/modemenu/sidebar)
  cli/              `cerebral` executable. Entry Sources/cerebral/Cerebral.swift
  canvas-extension/ Browser extension for the Canvas scrape (ios/ is a placeholder README)
config/             Read-only shipped config. tools/descriptors/*.json = 29 AUTHORITATIVE rich descriptors;
                    tools/*.json = 19 stricter-only overlays. Plus modes/ agents/ workflows/ references/ defaults/app.json
scripts/            Node gates: test.mjs (runner), generate-contracts, check-contract-drift, validate-{contracts,config,docs}
Tests/              Swift test targets    database/migrations/  0001–0015    evals/  model evals    .local/development/  dev state root
```

Runtime state root (`packages/core/Sources/CerebralCore/Workspace/WorkspacePaths.swift`):
development → `.local/development/`; packaged app → `~/Library/Application Support/CerebralHelm`.
Holds `overrides/`, `active-config.json`, `database/cerebral.sqlite`, `knowledge/`,
`backups/`, `events/`.

## Where state lives (don't duplicate it)

- **What's been built / changed** → `git log` and closed Linear tickets. Don't restate it.
- **What's planned / acceptance criteria** → Linear (NIC-xx). Source of truth for scope.
- **The contracts** → the JSON Schemas under `packages/contracts/schemas/`. Authoritative;
  TS/Swift are generated and drift-checked.
- **Decisions, rationale, gotchas** → the auto-memory files (`MEMORY.md` index + per-fact
  files). This is the running log — sharded so only relevant facts load.

## Verify, do not assume

Never assume the shape of a command/event/tool/storage/provider contract, how an
external API or OS feature behaves, which library version is available, or what a
**mock** implies about the real integration. Inspect the actual schema, type,
test, and config first. Do not invent fields, endpoints, permissions, lifecycle,
or error semantics. If it can't be verified, ask.

If sources conflict, requirements are unclear, or a decision would materially
affect architecture, behavior, security, or stored data — **stop and ask.**

## Work cadence

One coherent, commit-sized increment at a time:

1. Inspect the relevant code, contracts, tests, docs.
2. Resolve important uncertainty before editing.
3. Implement the smallest complete vertical slice that satisfies the request.
4. Add/update tests and docs.
5. Run the relevant verification.
6. Stop and return the work for review.

Do **not** roll into the next issue without another prompt. Do **not** create a
git commit unless the user explicitly asks — they review, commit, then prompt the
next step. Avoid unrelated refactors and opportunistic features.

**Completion report** for every increment: what was built · which files changed ·
what was run · key decisions · unresolved risks · the next logical increment
(named, not implemented).

## Engineering principles

Build the current increment with the full vision in mind, without implementing
future scope. Preserve these architectural truths:

- All input sources converge on **one versioned command bus**.
- UI expresses intent and renders state; it does not control the platform directly. All UI work follows the design spec + visual references.
- Platform / provider / model / storage behavior lives behind **replaceable adapters**; provider-neutral at the core boundary.
- Tools are narrow, explicit, typed, permission-aware, independently testable.
- **Risk classification and confirmation policy are deterministic and outside models.** Models may *propose* actions but never bypass policy or invoke unrestricted capabilities.
- **Descriptors are authoritative** (ADR-003): the rich descriptors in `config/tools/descriptors/` are the source of truth for risk/policy; `config/tools/*.json` is a **stricter-only overlay** (may tighten, never weaken — enforced in `ToolRegistryBuilder.register`). Known exception: `evals/lib/catalog.mjs` is a sanctioned prototype projection, to be replaced by the Swift one.
- `packages/` stays portable (**no AppKit**); `tools` and `knowledge` are **siblings** (both → `core`), never depend on each other; concretes compose in `packages/runtime-host`, and apps supply only capabilities and paths.
- Configuration lives outside hardcoded logic where practical.
- Durable personal state stays local, inspectable, portable, migration-safe, and survives updates. Never silently reset/replace/migrate user state — every stateful change has explicit behavior, tests, and a recovery path.
- **Contracts are versioned before adding production providers.** Missing integrations degrade gracefully rather than disabling the command surface.
- Tests cover contracts, regressions, migrations, failures, and security boundaries.

Don't over-engineer speculative abstractions. Add extension points only when the
North Star or the active programme plan establishes a real future requirement.

## Safety and state

Never bypass confirmation, permissions, allowlists, or tool policy for
convenience. Never expose secrets in code, config, logs, fixtures, or snapshots.
Treat destructive writes, external communication, process execution, financial
activity, authentication, and personal data as sensitive boundaries.

## Verification

Development is on macOS. `just` is **not installed** on this machine — use these
commands directly, not the `justfile` recipes.

- **Everything, one shot:** `node scripts/test.mjs` — toolchain check (requires Swift ≥ 6.0)
  → config/compatibility/contract validators → `check-contract-drift` → secret canary
  sweep → `validate-docs` → 11 `node --test` suites → `swift test` → dashboard unit tests
  and production build → Playwright (skipped unless browsers are installed).
- **Portable Swift core:** `swift test` at the repo root. The same plain command runs
  everywhere now, macOS and CI alike.
- **Keychain adapter contracts:** `CEREBRAL_KEYCHAIN_TESTS=1 swift test --filter MacAdapterTests`
  — opt-in, and must run isolated; it is unstable under the full suite's parallel load.
- **Dashboard** (`apps/dashboard`), in CI's order: `lint` → `typecheck` → `test --run` → `build`.
  **`typecheck` must stay `tsc -b`.** `tsconfig.json` is solution-style (`files: []`), so
  `tsc --noEmit` compiles nothing and exits 0. Note `tsc -b` also skips every test file.
- **macOS app target** — not covered by `swift test` and not in CI. Stage the dashboard,
  then build through the shared scheme (`apps/mac/README.md`): `apps/mac/scripts/build-dashboard-bundle.sh`,
  then from `apps/mac`: `xcodebuild -project CerebralHelm.xcodeproj -scheme CerebralHelm -configuration Debug -destination 'platform=macOS' build`.
- **Model evals** (`evals/README.md`) — opt-in, deliberately outside `scripts/test.mjs`
  (~45 GB of local models, tens of minutes): `ollama serve`, then `node evals/run.mjs --model=<tag>`.
  This is the **only** regression gate for a model or descriptor change.
- **CI** (`.github/workflows/ci.yml`, described in `docs/operations/ci.md`): six parallel
  jobs on every PR and on pushes to `dev`/`prod` — `contracts-config`, `dashboard`,
  `core-swift-linux` (swift:6.1 container), `core-swift-macos` (macos-15), `docs`, `secrets`.
  No Playwright job, no xcodebuild job.

**Playwright baselines are stale, not skipped by choice.** Every PNG in
`apps/dashboard/tests/visual/shell.spec.ts-snapshots/` is `-win32`, and
`playwright.config.ts` sets no `snapshotPathTemplate`, so macOS looks for `-darwin` and
finds nothing. The suite passes today only because `visual:available` fails and the
runner skips the step. Installing the browsers turns `node scripts/test.mjs` red until
the baselines are regenerated on macOS.
