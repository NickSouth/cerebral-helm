# PRE-UI Frontend — Handoff (how to pick up at E1)

Read this to resume the dashboard work cold. Companion docs: [STATUS.md](STATUS.md) (what's built), [PLAN.md](PLAN.md) (the roadmap).

## Read order (cheapest first)

1. `.agent/spec/UI-CONSTITUTION.md` — the binding UI rules + the **§2 per-increment checklist**. Every increment passes it.
2. [STATUS.md](STATUS.md) — current architecture + state shape + what each increment delivered.
3. The design spec `.agent/spec/CEREBRALHELM_DESIGN_SPEC.md` for the surface you're building (it beats the MVP-PRD for UI).
4. The relevant Linear ticket (NIC-xx) for acceptance criteria.

## Working cadence (from CLAUDE.md)

- **One commit-sized increment at a time.** Inspect → resolve uncertainty → implement the smallest complete vertical slice → tests + docs → verify → **stop and report**. Do not roll into the next increment without a prompt.
- **Do not commit unless asked.** The owner reviews each increment, commits it, then prompts the next. (Through **D5 is committed**; **D6 is uncommitted** in the working tree.)
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
| Bottom bar | `apps/dashboard/src/shell/PersistentBottomBar.tsx`; metrics source `regions.systemHealth`; live clock masked in `tests/visual/shell.spec.ts` (`.bottom-bar__clock`) |
| Heimlich center (E1 target) | `apps/dashboard/src/shell/CenterStage.tsx` (ambient field placeholder + greeting); state `heimlich.state` (`bridge/types.ts` `HeimlichState`); overlay `ConversationOverlay.tsx` (scrim to polish); reduced-motion is zeroed in `app.css` + the tokens `@media` block |
| Command surfaces | `apps/dashboard/src/shell/CommandSurface.tsx`, `commandSuggestions.ts`, `ConversationOverlay.tsx` |
| Widgets / apps registries | `apps/dashboard/src/widgets/`, `apps/dashboard/src/appCatalog/` |
| Config-reference gate | `scripts/validate-config.mjs` (+ `scripts/validate-contracts.mjs`) |
| Mode/workflow config | `config/modes/*.json`, `config/workflows/*.json`, `config/defaults/app.json` |
| Canonical fixtures | `fixtures/catalog/canonical-states.json` |

---

## What D6 settled (so you don't re-derive it)

- **The bottom bar is built** (`PersistentBottomBar.tsx`): three flex groups (left identity/weather · centered mode · right metrics/controls). Metrics read `regions.systemHealth`; degraded states are distinct (`stale` → amber marker, `unavailable`/offline → "Disconnected", `loading` → "Sampling…"). Weather + battery are honest-unavailable; Settings + Emergency are honest-disabled buttons (their surfaces are NIC-63 / later).
- **Mode accent on home only:** the centered mode label uses `--ch-accent-primary` (themed by `data-mode`) and is in the mode cross-fade transition set. There is no layout mode pre-Mac, so it always applies now — keep the "home only" caveat in mind when layout mode lands.
- **The clock is live `new Date()`** but **masked** in the visual spec (`mask: [.bottom-bar__clock]`) so the deterministic baseline never flakes. `PersistentBottomBar` takes an optional `now` prop for testability. No live timer/interval — it renders the time at render time (ticking is a later polish if wanted).
- **Visual tolerance gotcha:** the bottom-bar redesign came in **under the spec's `maxDiffPixelRatio: 0.02`** (full-page), so the baselines didn't actually change. Don't be surprised if a bottom-bar tweak shows no snapshot diff — per-region visual coverage is NIC-65/F1. Behavior is covered by unit tests instead.

## E1 — Heimlich state presentation (the generative field)

**Ticket:** NIC-60. **Design authority:** `.agent/spec/CEREBRALHELM_DESIGN_SPEC.md` §5.8 (Heimlich states + the per-state motion table around lines 219–234) + `.agent/spec/UI-CONSTITUTION.md` §2. This is the first **Phase E** increment.

Build the generative **WebGL ribbon/spark field** (OGL — already the approved lib per the bootstrap memory) behind a small `{ state, palette, audioLevel }` interface, with per-state presets + interpolation, **≥30fps with an offscreen/visibility pause**, and a **reduced-motion clamp**. Also **polish the conversation overlay/scrim** that D3 stubbed.

### What's already wired (consume, don't re-derive)

- **The center** is `CenterStage.tsx` — `section.heimlich` currently shows an eyebrow (`Heimlich · {state}`) + greeting as the ambient placeholder; the field renders *here, beneath* the conversation overlay (the center is never replaced — course-correction A.1).
- **State** is `useDashboardState().heimlich.state` (`HeimlichState`: idle/listening/thinking/acting/awaiting_confirmation/success/error/offline). Map each to a preset; interpolate on change. State label text stays (state is carried by text, never motion/color alone — §5.8).
- **Palette** is the active mode accent (`--ch-accent-*`, resolved by `data-mode`). The field should read the resolved accent, not hard-code per-mode colors.
- **Reduced motion** is already zeroed for CSS transitions (`app.css` + the tokens `@media (prefers-reduced-motion)` block). The WebGL field must honor `prefers-reduced-motion` too — clamp to a still/near-still frame.
- **Conversation overlay** (`ConversationOverlay.tsx`) composites over the field with a scrim; D3 left the scrim minimal. Polish it here.

### Decisions to settle FIRST

- **Visual determinism.** A live animating canvas will break the Playwright fullPage baselines. Decide the approach up front: mask the canvas (`mask: [...]`, like the clock), and/or freeze the field to a deterministic first frame under a test flag / `prefers-reduced-motion` (the visual spec already runs a reduced-motion case). Don't ship an unmasked animating canvas into the snapshot.
- **OGL dependency.** Confirm OGL is added to `apps/dashboard` deps (it isn't yet) and that the bundle/build stays green. Keep the WebGL behind a small typed module so the field is swappable and unit-testable without a real GL context (jsdom has no WebGL — guard construction).
- **Optional scope:** migrating the conversation from client-only `ConversationProvider` state to bridge-driven state is listed as optional — confirm with the owner before doing it (it's a separable change).

### Verify E1

- Dashboard: `test --run` + `build`; unit tests for state→preset mapping and the reduced-motion clamp (mock/guard the GL context). Don't assert pixels in unit tests.
- Visual: re-baseline + verify with the canvas masked or frozen; keep the §2 checklist and the reduced-motion case.
- Node/Swift: only if you touch a contract (you shouldn't).

After E1: **E2 (NIC-61 agent workspaces)** — see [PLAN.md](PLAN.md).
