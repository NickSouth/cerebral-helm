# PRE-UI Frontend — Status (what's been done)

**Epic:** NIC-50 (PRE-UI: the production React dashboard against the mock bridge).
**As of:** end of increment **D4**. Through **D3 is committed** (`4c698d6`); **D4 is in the working tree, uncommitted** (pending review). Confirm with `git log --oneline` / `git status`.

This is the "current reality" doc. For the roadmap see [PLAN.md](PLAN.md); to pick up work see [HANDOFF.md](HANDOFF.md).

---

## The dashboard today

`apps/dashboard` is a React 19 + Vite 5 + TypeScript app. It boots into **Executive mode** (the default), renders the three-zone shell populated with mock data for all four modes, lets you switch modes live (animated theme cross-fade), and opens a (mock) Heimlich conversation from the top launcher. Run it: `corepack pnpm --dir apps/dashboard dev` → http://localhost:5173.

### Architecture (layers, outermost contract first)

1. **Contracts** (`packages/contracts/`) — JSON Schemas are authoritative; TS/Swift are generated (`generate-contracts.mjs`). The dashboard consumes the bootstrap-state, event, and operation contracts.
2. **Bridge** (`apps/dashboard/src/bridge/`) — `CerebralBridge` is the transport-agnostic interface every consumer depends on (`cerebralBridge.ts`). `MockCerebralBridge` (`mockCerebralBridge.ts`) implements it: returns the composed bootstrap state, replays canonical lifecycle/failure fixtures (`eventFixtures.ts`), and handles operations. The native WKWebView transport swaps in here later with no component changes.
3. **Store** (`apps/dashboard/src/state/`) — `createBridgeStore(bridge, initialState)` (`bridgeStore.ts`) seeds synchronously and folds the bridge event stream into `DashboardState` via a pure reducer. Exposed through the `DashboardStore` seam (`dashboardState.ts`); the provider uses `useSyncExternalStore` (`DashboardStateProvider.tsx`). `useDashboardState()` / `useDashboardMode()` are the read API; `useBridge()` (`BridgeProvider.tsx`) is the write API.
4. **Conversation** (`state/ConversationProvider.tsx`) — Heimlich conversation as client-side session state, seeded from `bootstrap.heimlich.conversation`.
5. **Shell** (`apps/dashboard/src/shell/`) — `DashboardShell` composes LeftRail · CenterStage · RightRail · PersistentBottomBar. One shared composition renders all four modes from config — **no per-mode conditionals** (`useActiveMode.ts`).

### State shape (the contract everything binds to)

`DashboardBootstrapState` (`packages/contracts/schemas/bridge/bootstrap-state.schema.json`, mirrored in `apps/dashboard/src/bridge/types.ts`):

- top-level: `mode`, `project`, `summary`, `commandsToday`, `pendingConfirmations`, `uiState`
- `heimlich: { state, conversation: { open, transcript, input } }` — the center surface (always present)
- `expandedAgent: null | agentId` — the right-column-covering agent panel (default `null`)
- `modes: ModeView[4]` — all four resolved configs shipped **eagerly** (no-flash switching)
- `agents: AgentSummary[]` — the fixed roster (`availability` = config flag, `activity` = runtime status)
- `regions: { schedule, systemHealth, news, widgets: { left, right } }` — the **active** mode's data (resolved on switch)

The eager `modes`/`agents` bundle + a per-state `regions` snapshot are composed by the mock; switching emits a `config.changed` event the reducer folds in (keeps the bundle, swaps the snapshot).

---

## Increments delivered

| # | Ticket | What it delivered | State |
|---|---|---|---|
| **Foundation** | NIC-51 | Constitution, token system (`data-mode`), reference-resolution gate, Playwright+axe guardrail, app container + state seam | committed |
| **A1** | NIC-117 | Widget registry (8 ids) + app catalog (17 ids) + unified reference-resolution gate (`validate-config.mjs` **and** `validate-contracts.mjs`); widget data fixtures | committed |
| **A2** | NIC-117 d | Expanded `DashboardBootstrapState` (eager `modes` + `agents` + active `regions`); per-mode + degraded fixtures; regenerated TS/Swift | committed |
| **Course-correction** | (owner) | Replaced `activeSurface` with `heimlich` + `expandedAgent`; reconciled design spec §5.10/§16/§5.5/§5.7/§9.3 + constitution (Heimlich owns center; agent overlay covers right column only; two input loci; **constant density**; animated mode switch) | committed |
| **A3** | NIC-117 e | `getRecentActivity` read-surface op (FR-OBS-04) on the bridge contract + fixtures | committed |
| **B1** | NIC-52 | `CerebralBridge` interface + `MockCerebralBridge` (replays all lifecycle/failure fixtures) | committed |
| **B2** | NIC-52 | Event-driven store behind the seam (`useSyncExternalStore`); replaced the static store | committed |
| **C1** | NIC-53 | Three-zone shell + panel primitive + responsive collapse + bottom-bar track (honest-unavailable placeholders) | committed |
| **D1** | NIC-54 | Config-driven mode view — Quick Apps (category glyphs), 4+4 quick actions (labelled, greyed), schedule/health/news panels, registry-driven widgets, greeting; one view, four modes, no conditionals | committed |
| **D2** | NIC-54 / 117h | Mode switcher wired to `applyMode` (animated theme cross-fade, no remount); **Executive is the default** (ADR-007) — aligned frontend seed + bootstrap fixture + tests to the already-Executive config | committed |
| **D3** | NIC-58 | Two command loci (persistent top launcher + in-conversation docked input), capability-aware suggestions, conversation overlay; **no floating modal palette** | committed |
| **D4** | NIC-117 b / ex-NIC-113 | Wired the trivial `capture-note` quick action → `bridge.captureNote` (honest acknowledgement via the new `ConversationProvider.acknowledge`); others stay greyed placeholders. Added the **quickActions→workflow resolution gate** (`validateQuickActionWiring` in `validate-config.mjs`) + wired-action manifest (`apps/dashboard/src/shell/quickActions.manifest.json`, **loose**: unknown ids = placeholders) + `scripts/quick-action-wiring.test.mjs` | **uncommitted** |

Cancelled as duplicates (folded into NIC-54): NIC-55/56/57.

---

## Authoritative decisions in force

- **Executive is the default mode** — ADR-007; `config/defaults/app.json` is the single authority; the UI never hard-codes a default.
- **Heimlich always owns the center**; chat is a translucent overlay, never a replacement.
- **Agent workspaces cover the right column only** (the seam is reserved; the panel is NIC-61).
- **Two command loci**, no floating palette (course-correction C).
- **Animated mode transition**, not instant/pending; all four palettes preload (course-correction D.1).
- **Constant density across modes** — Entertainment is *not* lighter (course-correction D.2, supersedes the original NIC-57/NIC-54 AC).
- **Quick-app icons** = generic monochrome category glyphs pre-Mac; real OS icons on Mac.
- **Honest-unavailable** for anything not wired; nothing fake-successful.

## Verification state (all green except a known environmental flake)

- Dashboard: **57 unit tests** (9 files) + build; **Playwright 10/10** (Chromium+WebKit × compact/laptop/external + reduced-motion + axe), re-baselined for the enabled `capture-note` slot — baselines are **win32-only** (`apps/dashboard/tests/visual/shell.spec.ts-snapshots/`).
- Node contract gates: `validate-config` (now incl. the quick-action wiring gate), `validate-contracts` (37 schemas / 72 valid / 39 invalid fixtures), `check-contract-drift`, the `scripts/*.test.mjs` suite (incl. `quick-action-wiring.test.mjs`) — all green.
- Swift: compiles; **243/246** `swift test` — the 3 failures are `SchemaMigratorTests` reading `database/migrations/*.sql` as empty, a **OneDrive dehydration** flake unrelated to this work (see [HANDOFF.md](HANDOFF.md) § Gotchas).
