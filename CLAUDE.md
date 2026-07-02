# CLAUDE.md

This file is auto-loaded into every session. It is a **router**, not a manual: it
orients you fast and points at the authoritative source for each thing. Read the
pointer, then read the source — do not assume the contents from here.

> Adapted from `.agent/AGENTS.md`, which remains the longer-form companion. If the
> two ever diverge, this file wins for day-to-day work; reconcile them.

## What this is

CerebralHelm is a local-first agentic desktop environment for macOS, centered on
the assistant **Heimlich**: a persistent dashboard, command surface, mode engine,
knowledge system, and launcher for narrow tools and specialized agents. It is
**not** an OS replacement or an unrestricted chatbot. Goal: a reliable,
context-aware front door to the user's digital life. **Core principle: useful
before intelligent.**

The MVP builds the deterministic foundation first, on a Windows dev machine with
mock adapters (no AppKit yet). Voice, mobile, models, integrations, and agents
must **extend the same contracts**, never fork parallel systems.

Canonical vocabulary: Modes = Executive / Developer / School / Entertainment ·
Agent surfaces = Research Analyst / Financial Advisor / Project Manager / System
Janitor · Durable knowledge = Markdown + SQLite · Vector indexes = disposable and
rebuildable.

## Start here (orientation, cheapest first)

1. **The user's latest explicit instruction** — always outranks everything below.
2. **Scope & acceptance criteria** → [`.agent/spec/MVP-PRD.md`](.agent/spec/MVP-PRD.md). Controls *current* scope.
3. **Approved stack & impl decisions** → [`.agent/spec/TECH-STACK.md`](.agent/spec/TECH-STACK.md).
4. **UI/visual authority** → [`.agent/spec/CEREBRALHELM_DESIGN_SPEC.md`](.agent/spec/CEREBRALHELM_DESIGN_SPEC.md) + [`wiki/CerebralHelm-Visual-Design-Reference.pdf`](wiki/CerebralHelm-Visual-Design-Reference.pdf). **Precedence: the design spec beats the MVP-PRD for UI questions.** Day-to-day dashboard work reads the distilled [`.agent/spec/UI-CONSTITUTION.md`](.agent/spec/UI-CONSTITUTION.md) (tokens, grammar, per-increment checklist); the design spec still wins if they diverge.
5. **Long-term intent (future compatibility, not current scope)** → [`wiki/NORTH-STAR.md`](wiki/NORTH-STAR.md).
6. **Hard architecture boundaries** → [`docs/architecture/repository-boundaries.md`](docs/architecture/repository-boundaries.md).
7. **Key decisions** → ADRs in [`docs/adr/`](docs/adr/): 001 AppKit+WKWebView shell · 002 single command lifecycle · 003 internal tool registry & risk policy · 004 versioned bridge.

The MVP-PRD controls current scope; the North Star informs future compatibility
but does **not** auto-place future features inside the MVP.

## Current frontier

> Keep this line current — it's the highest-value, fastest-stale pointer in the repo.

- **Done:** NIC-9 (command spine), **NIC-10 PRE-SAFETY** (registry, executor, policy, confirmation, redaction), and **PRE-MODE** — NIC-38 (deterministic config-driven action/workflow planner) and NIC-39 (mode state + session persistence), with the live `WorkflowActionPlanner` bound in the runtime. Full stack runs through the live `cerebral` CLI; full Swift test suite green (run `swift test` for the current count). All PRE-MODE child tickets (NIC-36..41, incl. NIC-41 data-root separation) are done; only the parent epic NIC-35 remains open (close once verified).
- **Next chunk (separate issue):** NIC-42 PRE-DATA (SQLite + durable `KnowledgeService` + cross-invocation confirmation persistence). NIC-33 ships this behind **ports** with mock/stub bindings, so it is not blocked pre-Mac.
- **Tech debt NIC-107..NIC-111 (Linear, `Tech Debt`):** all five implemented + green; staged/uncommitted pending review. Out of NIC-111: **`app.open`/`url.open`/`hook.run` are deliberately Mac-only** (descriptors say so), so the pre-Mac CLI surface is **notes + status + mode**; those three terminate `.unavailable` pre-Mac by design.

## Where state lives (don't duplicate it)

- **What's been built / changed** → `git log` and closed Linear tickets. Don't restate it.
- **What's planned / acceptance criteria** → Linear (NIC-xx). Source of truth for scope.
- **The contracts** → the JSON Schemas under `packages/contracts/`. Authoritative; TS/Swift are generated.
- **Decisions, rationale, gotchas** → the auto-memory files (`MEMORY.md` index + per-fact files). This is the running log — sharded so only relevant facts load.

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
- **Descriptors are authoritative** (ADR-003): rich tool descriptors are the source of truth for risk/policy; `config/tools/*.json` is a **stricter-only overlay** (may tighten, never weaken).
- `packages/` stays portable (**no AppKit**); `tools` and `knowledge` are **siblings** (both → `core`), never depend on each other; compose concretes at the app layer.
- Configuration lives outside hardcoded logic where practical.
- Durable personal state stays local, inspectable, portable, migration-safe, and survives updates. Never silently reset/replace/migrate user state — every stateful change has explicit behavior, tests, and a recovery path.
- **Contracts are versioned before adding production providers.** Missing integrations degrade gracefully rather than disabling the command surface.
- Tests cover contracts, regressions, migrations, failures, and security boundaries.

Don't over-engineer speculative abstractions. Add extension points only when the
North Star or MVP-PRD establishes a real future requirement.

## Safety and state

Never bypass confirmation, permissions, allowlists, or tool policy for
convenience. Never expose secrets in code, config, logs, fixtures, or snapshots.
Treat destructive writes, external communication, process execution, financial
activity, authentication, and personal data as sensitive boundaries.

## Verification

- **JS/contract gates:** `node scripts/test.mjs` (runner); contract/config validation via `scripts/validate-contracts.mjs`, `scripts/validate-config.mjs`, `scripts/check-contract-drift.mjs`. Linux/CI runs plain `swift test`.
- **Swift on this Windows dev box:** the default shell often can't find `swift` or fails with duplicate `PATH` errors. Use the cleaned-environment pattern below, and a scratch path **outside OneDrive** (OneDrive's filter breaks symlinks and locks `.build`).

```powershell
$swiftRoot = 'C:\Users\nickr\AppData\Local\Programs\Swift'
$msvcRoot = 'C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.44.35207'
$winKitRoot = 'C:\Program Files (x86)\Windows Kits\10'
$winKitVersion = '10.0.22621.0'
$swiftSDK = "$swiftRoot\Platforms\6.3.2\Windows.platform\Developer\SDKs\Windows.sdk"
$originalPath = [System.Environment]::GetEnvironmentVariable('Path', 'Process')
[System.Environment]::SetEnvironmentVariable('PATH', $null, 'Process')
[System.Environment]::SetEnvironmentVariable('Path', "$swiftRoot\Toolchains\6.3.2+Asserts\usr\bin;$swiftRoot\Runtimes\6.3.2\usr\bin;$msvcRoot\bin\Hostx64\x64;$winKitRoot\bin\$winKitVersion\x64;$winKitRoot\bin\x64;$originalPath", 'Process')
[System.Environment]::SetEnvironmentVariable('SDKROOT', $swiftSDK, 'Process')
[System.Environment]::SetEnvironmentVariable('INCLUDE', "$msvcRoot\include;$winKitRoot\Include\$winKitVersion\ucrt;$winKitRoot\Include\$winKitVersion\shared;$winKitRoot\Include\$winKitVersion\um;$winKitRoot\Include\$winKitVersion\winrt", 'Process')
[System.Environment]::SetEnvironmentVariable('LIB', "$msvcRoot\lib\x64;$winKitRoot\Lib\$winKitVersion\ucrt\x64;$winKitRoot\Lib\$winKitVersion\um\x64", 'Process')
& "$swiftRoot\Toolchains\6.3.2+Asserts\usr\bin\swift.exe" test --scratch-path 'C:\Users\nickr\AppData\Local\cerebral-build'
```

`swift-argument-parser` is pinned to `1.1.x` on purpose (1.2.0+ uses symlinked
plugin sources SwiftPM-on-Windows can't traverse). Enable Windows **Developer
Mode** so git can materialize package symlinks. Full detail + failure signatures:
[`.agent/AGENTS.md`](.agent/AGENTS.md) § Windows Swift Verification.
