# PRE-UI Frontend — Handoff (how to pick up at D6)

Read this to resume the dashboard work cold. Companion docs: [STATUS.md](STATUS.md) (what's built), [PLAN.md](PLAN.md) (the roadmap).

## Read order (cheapest first)

1. `.agent/spec/UI-CONSTITUTION.md` — the binding UI rules + the **§2 per-increment checklist**. Every increment passes it.
2. [STATUS.md](STATUS.md) — current architecture + state shape + what each increment delivered.
3. The design spec `.agent/spec/CEREBRALHELM_DESIGN_SPEC.md` for the surface you're building (it beats the MVP-PRD for UI).
4. The relevant Linear ticket (NIC-xx) for acceptance criteria.

## Working cadence (from CLAUDE.md)

- **One commit-sized increment at a time.** Inspect → resolve uncertainty → implement the smallest complete vertical slice → tests + docs → verify → **stop and report**. Do not roll into the next increment without a prompt.
- **Do not commit unless asked.** The owner reviews each increment, commits it, then prompts the next. (Through **D4 is committed**; **D5 is uncommitted** in the working tree.)
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
| Confirmation surface | `apps/dashboard/src/shell/ConfirmationOverlay.tsx`; disclosure type + runtime `activeConfirmation` in `bridge/types.ts` / `state/dashboardState.ts`; reducer `confirmation.changed` in `state/bridgeStore.ts`; replay + clear in `bridge/mockCerebralBridge.ts`; fixture event `confirmationBridgeEvent` (`bridge/eventFixtures.ts`) |
| Bottom bar (D6 target) | `apps/dashboard/src/shell/PersistentBottomBar.tsx`; metrics source `regions.systemHealth` (`bridge/types.ts`); region/metric states are `ready/empty/stale/unavailable` |
| Command surfaces | `apps/dashboard/src/shell/CommandSurface.tsx`, `commandSuggestions.ts`, `ConversationOverlay.tsx` |
| Widgets / apps registries | `apps/dashboard/src/widgets/`, `apps/dashboard/src/appCatalog/` |
| Config-reference gate | `scripts/validate-config.mjs` (+ `scripts/validate-contracts.mjs`) |
| Mode/workflow config | `config/modes/*.json`, `config/workflows/*.json`, `config/defaults/app.json` |
| Canonical fixtures | `fixtures/catalog/canonical-states.json` |

---

## What D5 settled (so you don't re-derive it)

- **Confirmations are event-driven runtime state, not bootstrap config** (owner decision). The disclosure arrives via the `confirmation.changed` event (its payload is open — `additionalProperties: true` — so no event-schema change), and the reducer folds it into a **runtime-only** `activeConfirmation` field. `DashboardState = DashboardBootstrapState & { activeConfirmation?: ConfirmationDisclosure | null }`. The bootstrap-state contract was **not** changed (no codegen/Swift). This is the template for any future runtime-only field.
- **The disclosure type is hand-mirrored** in `bridge/types.ts` (`ConfirmationDisclosure` + nested types), the same convention as the bootstrap-state mirror — it is **not** imported from generated contracts. If the disclosure schema changes, update this mirror too.
- **Neutral system blue is mandatory** (§9): the window uses the mode-invariant `--ch-confirm-accent` / `--ch-confirm-surface` tokens and **never** `--ch-accent-*`. Don't theme it per mode.
- **Approve is never default-focused** — the contract constrains `choices.defaultFocusedChoice` to `review`/`cancel`, and that button gets initial focus. Keep this invariant.
- **The bridge owns clearing.** The UI dispatches `decideConfirmation`; the *mock* emits a `confirmation.changed` with `confirmation: null` to clear (and the real bridge would also drive the lifecycle forward). The overlay never clears itself UI-locally. `replayConfirmation()` on the mock surfaces the canonical fixture for tests/demos.

## D6 — persistent bottom bar

**Ticket:** NIC-59. **Design authority:** `.agent/spec/CEREBRALHELM_DESIGN_SPEC.md` (§ bottom bar — note §8 "the bar changes accent with the active mode **on the home dashboard only**; confirmation surfaces do not inherit mode color") + `.agent/spec/UI-CONSTITUTION.md` §2.

Today `PersistentBottomBar.tsx` is a reserved track with a single honest "Metrics — not implemented" placeholder. D6 builds the real bar: Heimlich state, mode (accent on home only), context, CPU/mem/network/time, settings, emergency — with **distinct loading/stale/unavailable/disconnected** metric states, and **weather + battery honest-unavailable pre-Mac**.

### What's already wired (consume, don't re-derive)

- **Metric data** is in state at `regions.systemHealth` (`bridge/types.ts` `SystemHealthRegion`): `state` (`ready/empty/stale/unavailable`), `cpuPercent?`, `memoryPercent?`, `network` (`MetricChannel { state, label }`), and `battery` (`MetricChannel` — already `unavailable` pre-Mac, see the existing `mode.developer.ready` test for the "Battery — requires the macOS host" assertion).
- **Capability degradation:** the reducer already flips `regions.systemHealth.state` to `stale` on a `bridge.capability.changed` (system.metrics unavailable) event (`bridgeStore.ts`). Render the `stale`/`unavailable` channel states distinctly — don't invent new state.
- **Heimlich state** label via `heimlichStateLabel` (`shell/labels.ts`); **mode** from `useDashboardState().mode`.
- **No `Date.now()` in render paths** that feed screenshots — the visual fixture is deterministic (fixed clocks). If you show a clock, drive it from state/props, not a live timer, or the Playwright baselines will flake.

### Decisions to settle FIRST

- **Time/weather source.** There's no `time` or `weather` field in the bootstrap state today. Weather + battery are honest-unavailable pre-Mac (just render the unavailable channel). For the clock: decide whether time comes from state (preferred — keeps screenshots deterministic) or is explicitly excluded from the visual snapshot. Don't add a live `Date` timer that breaks visual determinism.
- **Emergency control.** Confirm what "emergency" does pre-Mac — almost certainly an honest-disabled control (no capability to wire yet), consistent with the honest-unavailable rule.

### Verify D6

- Node: `validate-config` + `validate-contracts` + `check-contract-drift` (no schema change expected).
- Dashboard: `test --run` + `build`; unit tests for the distinct metric states (ready vs stale vs unavailable) and mode-accent-on-home-only.
- Visual: **re-baseline and verify** — the bottom bar changes appearance, so the idle-shell screenshots WILL change. Keep the §2 checklist.

After D6, Phase D is complete; next is **Phase E (E1 NIC-60 Heimlich WebGL field, …)** — see [PLAN.md](PLAN.md).
