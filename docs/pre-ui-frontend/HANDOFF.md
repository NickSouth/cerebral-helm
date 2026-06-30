# PRE-UI Frontend — Handoff (how to pick up at D4)

Read this to resume the dashboard work cold. Companion docs: [STATUS.md](STATUS.md) (what's built), [PLAN.md](PLAN.md) (the roadmap).

## Read order (cheapest first)

1. `.agent/spec/UI-CONSTITUTION.md` — the binding UI rules + the **§2 per-increment checklist**. Every increment passes it.
2. [STATUS.md](STATUS.md) — current architecture + state shape + what each increment delivered.
3. The design spec `.agent/spec/CEREBRALHELM_DESIGN_SPEC.md` for the surface you're building (it beats the MVP-PRD for UI).
4. The relevant Linear ticket (NIC-xx) for acceptance criteria.

## Working cadence (from CLAUDE.md)

- **One commit-sized increment at a time.** Inspect → resolve uncertainty → implement the smallest complete vertical slice → tests + docs → verify → **stop and report**. Do not roll into the next increment without a prompt.
- **Do not commit unless asked.** The owner reviews each increment, commits it, then prompts the next. (Through **D2 is committed**; **D3 is uncommitted** in the working tree.)
- **Consume, never re-derive.** Tokens via `data-mode` + the token source; mode color never via a per-mode conditional. State via the `DashboardStore` seam (`useDashboardState`), dispatch via `useBridge`. New values go in the token source + the constitution, never inlined.
- **Honest-unavailable** for anything not wired; never fake-successful.

## Verification commands

All from the repo root. The dashboard uses pnpm via corepack.

```bash
# Dashboard unit tests + build (run for every dashboard increment)
corepack pnpm --dir apps/dashboard test --run
corepack pnpm --dir apps/dashboard build

# Visual regression (re-baseline after an INTENTIONAL visual change, then verify)
corepack pnpm --dir apps/dashboard exec playwright test --update-snapshots
corepack pnpm --dir apps/dashboard exec playwright test

# Node contract/config gates (run when you touch packages/contracts or config/ or scripts/)
node scripts/validate-config.mjs
node scripts/validate-contracts.mjs
node scripts/check-contract-drift.mjs
node --test scripts/contracts-bridge.test.mjs scripts/fixture-catalog.test.mjs scripts/config-reference-resolution.test.mjs

# If you changed a contract SCHEMA: rehydrate+pin, regenerate, then re-run drift
attrib +P -U "packages\contracts\*" /S /D     # (PowerShell) avoid the OneDrive dehydration trap
node scripts/generate-contracts.mjs
```

**Dev server:** `corepack pnpm --dir apps/dashboard dev` → http://localhost:5173.

**Swift** (only if you touch `packages/`/contracts that Swift consumes) — use the cleaned-environment pattern from `CLAUDE.md` § Verification and a scratch path **outside OneDrive** (`--scratch-path 'C:\Users\nickr\AppData\Local\cerebral-build'`).

## Gotchas (all real, all hit during this work)

- **OneDrive Files-On-Demand dehydration.** Idle files become cloud-only placeholders that Node/Swift may read as *empty*, faking contract drift or empty `.sql` migrations. Symptom: `check-contract-drift` red with a clean tree, or `SchemaMigratorTests` 3 failures (`fileSQL → ""`). Fix: rehydrate+pin (`attrib +P -U "<dir>\*" /S /D`, or Explorer → "Always keep on this device"). **Never run `generate-contracts.mjs` while files are dehydrated** — it deletes the missing types.
- **CRLF vs `check-contract-drift`.** `core.autocrlf=true` + no `.gitattributes` ⇒ git checks generated files out as CRLF while the generator writes LF, so the byte-exact drift compare is chronically red on Windows. Running `generate-contracts.mjs` makes it pass immediately. Real fix is a `.gitattributes` (a tech-debt chip was spawned for this).
- **Codegen namespace collisions.** quicktype shares ONE type namespace across all schemas. A new schema whose nested property names duplicate existing ones (e.g. `freshness`, `theme`, `action`) **renames the incumbent generated type** and breaks Swift consumers. Fix: give every inline nested object/enum a unique `title`. **Acceptance check after any schema change:** regenerate, then diff `(struct|enum)` names HEAD-vs-new — no incumbent may be *removed*. Then `swift test`.
- **Visual baselines are win32-only.** `apps/dashboard/tests/visual/shell.spec.ts-snapshots/*.png`. Cross-platform/CI baselines are NIC-65. Re-baseline after intentional visual changes and verify.
- **Vitest is scoped to `src/**/*.test.{ts,tsx}`** so it never collects the Playwright specs under `tests/visual`. Keep unit tests in `src`.

## Key file map

| Concern | File(s) |
|---|---|
| Bridge contract (interface) | `apps/dashboard/src/bridge/cerebralBridge.ts` |
| Mock bridge + event replay | `apps/dashboard/src/bridge/mockCerebralBridge.ts`, `eventFixtures.ts` |
| Dashboard state types | `apps/dashboard/src/bridge/types.ts` (mirror of `packages/contracts/.../bootstrap-state.schema.json`) |
| Store + reducer | `apps/dashboard/src/state/bridgeStore.ts`; seam `dashboardState.ts`; providers `DashboardStateProvider.tsx` / `BridgeProvider.tsx` / `ConversationProvider.tsx`; runtime factory `bootstrapStore.ts` |
| Shell | `apps/dashboard/src/shell/DashboardShell.tsx` + `LeftRail`/`CenterStage`/`RightRail`/`PersistentBottomBar` |
| Active-mode binding | `apps/dashboard/src/shell/useActiveMode.ts` |
| Quick actions (D4 target) | `apps/dashboard/src/shell/QuickActions.tsx` |
| Command surfaces | `apps/dashboard/src/shell/CommandSurface.tsx`, `commandSuggestions.ts`, `ConversationOverlay.tsx` |
| Widgets / apps registries | `apps/dashboard/src/widgets/`, `apps/dashboard/src/appCatalog/` |
| Config-reference gate | `scripts/validate-config.mjs` (+ `scripts/validate-contracts.mjs`) |
| Mode/workflow config | `config/modes/*.json`, `config/workflows/*.json`, `config/defaults/app.json` |
| Canonical fixtures | `fixtures/catalog/canonical-states.json` |

---

## D4 — wire trivial quick actions + the quickActions→workflow gate

**Tickets:** NIC-117 (b) / ex-NIC-113. **Scope:** small and incremental — do **not** try to wire all eight actions.

Today `QuickActions.tsx` renders the active mode's eight `quickActions` ids as labelled, **greyed, disabled** slots. D4 turns the *trivial* ones live and adds a resolution gate so wired action ids can't dangle.

### Part 1 — wire the trivial action(s)

- The cheapest real wiring is `capture-note` → `bridge.captureNote(...)` (the bridge op already exists and the mock acknowledges it). Optionally `search-notes` → `bridge.searchNotes(...)`.
- Use `useBridge()` to dispatch (same pattern as the mode switcher in `RightRail.tsx`). Keep the result honest — e.g. surface an acknowledgement in the Heimlich conversation (`ConversationProvider`), don't fake a richer result.
- Every other action **stays greyed/disabled** ("coming soon"). Per NIC-117(b), placeholders are not a blocker; wire incrementally.

### Part 2 — the quickActions→workflow resolution gate (ex-NIC-113)

- **Intent:** a *wired* quick-action id must resolve (to a `config/workflows/*.json` workflow id, or a known handler) — a dangling wired action is a build failure. **Placeholders are allowed** without a workflow (most actions are placeholders today; the gate "follows the wiring, not before").
- **Design decision to make:** how to mark "wired vs placeholder." Mirror the existing gate idiom in `scripts/validate-config.mjs` (`readRegistered*` + `validateMode*` + a lockstep manifest, exactly like the theme-token / widget / app gates already there). A clean option: a small **wired-action manifest** (action id → workflow id / handler) that the gate resolves; ids not in the manifest are treated as placeholders. Whatever you choose, also wire it into `validate-contracts.mjs` for the invalid-fixture path (see how the theme/widget/app gate is dual-wired there) and add an invalid fixture under `packages/contracts/fixtures/invalid/config/modes/`.
- Note: `config/workflows/` currently holds only the four mode-entry workflows; `WorkflowActionPlanner` (Swift) resolves an action id to a workflow at runtime and already errors structurally on an unknown action.

### Verify D4

- Node: `validate-config.mjs` + `validate-contracts.mjs` + `check-contract-drift` + the resolution-gate test (add one mirroring `scripts/config-reference-resolution.test.mjs`).
- Dashboard: `test --run` + `build`; add a unit test that the wired action dispatches and the unwired ones stay disabled.
- Visual: re-baseline only if the quick-action appearance changes (a wired action may look enabled vs greyed).
- Swift: only if you touch a contract schema (you likely won't).

After D4, the next increments are **D5 (NIC-62 confirmation surface)** then **D6 (NIC-59 bottom bar)** — see [PLAN.md](PLAN.md).
