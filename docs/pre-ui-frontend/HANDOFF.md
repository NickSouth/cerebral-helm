# PRE-UI Frontend — Handoff (how to pick up at D5)

Read this to resume the dashboard work cold. Companion docs: [STATUS.md](STATUS.md) (what's built), [PLAN.md](PLAN.md) (the roadmap).

## Read order (cheapest first)

1. `.agent/spec/UI-CONSTITUTION.md` — the binding UI rules + the **§2 per-increment checklist**. Every increment passes it.
2. [STATUS.md](STATUS.md) — current architecture + state shape + what each increment delivered.
3. The design spec `.agent/spec/CEREBRALHELM_DESIGN_SPEC.md` for the surface you're building (it beats the MVP-PRD for UI).
4. The relevant Linear ticket (NIC-xx) for acceptance criteria.

## Working cadence (from CLAUDE.md)

- **One commit-sized increment at a time.** Inspect → resolve uncertainty → implement the smallest complete vertical slice → tests + docs → verify → **stop and report**. Do not roll into the next increment without a prompt.
- **Do not commit unless asked.** The owner reviews each increment, commits it, then prompts the next. (Through **D3 is committed**; **D4 is uncommitted** in the working tree.)
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
| Quick actions | `apps/dashboard/src/shell/QuickActions.tsx`; wiring `quickActionHandlers.ts` + `quickActions.manifest.json`; gate `validateQuickActionWiring` in `scripts/validate-config.mjs` (test `scripts/quick-action-wiring.test.mjs`) |
| Confirmations (D5 target) | state `pendingConfirmations` (`bridge/types.ts`); op `bridge.decideConfirmation`; event `confirmation.changed` (`bridge/eventFixtures.ts`, reducer in `state/bridgeStore.ts`) |
| Command surfaces | `apps/dashboard/src/shell/CommandSurface.tsx`, `commandSuggestions.ts`, `ConversationOverlay.tsx` |
| Widgets / apps registries | `apps/dashboard/src/widgets/`, `apps/dashboard/src/appCatalog/` |
| Config-reference gate | `scripts/validate-config.mjs` (+ `scripts/validate-contracts.mjs`) |
| Mode/workflow config | `config/modes/*.json`, `config/workflows/*.json`, `config/defaults/app.json` |
| Canonical fixtures | `fixtures/catalog/canonical-states.json` |

---

## What D4 settled (so you don't re-derive it)

- **Wired-action model is loose:** `apps/dashboard/src/shell/quickActions.manifest.json` lists only the *wired* ids → a `{ handler }` or `{ workflow }` target. Any id **not** in the manifest is an allowed placeholder (greyed/disabled). Today only `capture-note → { handler: captureNote }` is wired.
- **The gate** is `validateQuickActionWiring` (`scripts/validate-config.mjs`): each wired target must resolve to a `config/workflows/*.json` id or a declared `handlers[]` entry; exactly one of workflow/handler. It runs inside `validateRepositoryConfig` and is unit-tested in `scripts/quick-action-wiring.test.mjs`. Because the model is loose, a *mode* can't dangle on its own, so there is **no invalid mode fixture** — the negative cases live in the gate's unit test.
- **Honest acknowledgement channel:** `ConversationProvider.acknowledge(text)` appends a Heimlich-authored message (no user turn, no command dispatch). Reuse it for any action that needs to report a bridge result.
- To wire another action: add it to the manifest, add a handler impl in `quickActionHandlers.ts` (keyed by handler name) or a workflow file, done. Slot enable/disable in `QuickActions.tsx` follows the manifest automatically.

## D5 — universal confirmation surface

**Ticket:** NIC-62. **Design authority:** `.agent/spec/CEREBRALHELM_DESIGN_SPEC.md` (the confirmation/review window) + `.agent/spec/UI-CONSTITUTION.md` §2 checklist.

A neutral-blue review window that shows a pending confirmation in full (no truncation of what will happen), with **approve NOT the default-focused control**, a keyboard flow, and visible expiry/invalidation. It submits the decision via `bridge.decideConfirmation({ id, decision })` (op already exists; the mock acks).

### Scope decision to resolve FIRST (it's a contract question)

- **The state today carries only a count.** `DashboardBootstrapState.pendingConfirmations` is a `number` (`bridge/types.ts:133`), and the `confirmation.changed` event is currently *observed but not interpreted* (`bridgeStore.ts` comment). To render full disclosure you need the actual confirmation payload — title, the action/tool being confirmed, risk, disclosure fields, expiry.
- There **is** a contract for the disclosure: `packages/contracts/schemas/tools/confirmation-disclosure.schema.json` (+ valid fixtures under `fixtures/valid/tools/confirmations/`). Decide how it reaches the UI: expand the bootstrap-state contract to carry a `confirmations: ConfirmationDisclosure[]` (and have `confirmation.changed` fold into it), versus a separate read op. **This is a schema change** → the codegen-namespace-collision + OneDrive-dehydration + Swift gotchas above all apply (regenerate, diff `(struct|enum)` names HEAD-vs-new, `swift test`). Settle the shape before building (see the "settle shapes, defer content" memory).
- If the owner wants to keep D5 purely presentational against a mock for now, an alternative is to drive it from the existing confirmation fixtures via the mock bridge without a bootstrap-state change — confirm which they want.

### Verify D5

- Node: `validate-config` + `validate-contracts` + `check-contract-drift` (+ regenerate & Swift if you touch a schema).
- Dashboard: `test --run` + `build`; unit tests for the keyboard flow, approve-not-default-focus, and `decideConfirmation` dispatch.
- Visual: re-baseline (new surface) and verify; keep the §2 checklist.

After D5: **D6 (NIC-59 bottom bar)** — see [PLAN.md](PLAN.md).
