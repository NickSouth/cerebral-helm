# Widget Work Handoff

> **Living document.** This is the shared map of code, decisions, and patterns for the
> dashboard **widget sprint** (the NIC-121 widget programme). Every widget we build should
> follow the conventions here. When you make a decision or discover a pattern that future
> widget work should reuse, **add it to this file in the same change.**
>
> Precedence: this doc is a convenience map, not an authority. If it ever conflicts with the
> design spec, `MVP-PRD.md`, the JSON-Schema contracts, or the code, those win — reconcile
> this file to them.

First blueprint widget: **NIC-131 Active Repos** (`repositories`). It is the reference
implementation for everything below — when in doubt, read how `repositories` does it.

---

## 1. The widget roster (source of truth)

The registered widget ids live in [`apps/dashboard/src/widgets/widgets.ts`](../apps/dashboard/src/widgets/widgets.ts)
(mirrored by `widgets.manifest.json`, kept in lockstep by `widgets.test.ts`). A mode config's
`widgets.left` / `widgets.right` must reference one of these ids or the config gate fails.

| id | side | mode(s) | status |
|---|---|---|---|
| `market-brief` | left | Executive | fixture-backed (not live) |
| `project-git-status` | left | Developer | fixture-backed |
| `deadlines` | left | School | fixture-backed |
| `spotify` | left | Entertainment | fixture-backed |
| `projects` | right | Executive | fixture-backed |
| `repositories` | right | Developer | **LIVE (NIC-131) — blueprint** |
| `courses` | right | School | fixture-backed |
| `media-list` | right | Entertainment | fixture-backed |

"fixture-backed" = the slot renders from the bootstrap/fixture `WidgetData`; there is no live
producer yet. Making one live = following §4.

---

## 2. Architecture: how a widget goes live

The data path, end to end. This is the reusable mechanism (built once in NIC-131); every new
live widget plugs into it without touching the plumbing.

```
native producer (actor)                web (React)
  reads domain state          ─────►   widget.data.changed event
  maps → WidgetData envelope           reducer folds into DashboardState.liveWidgets[widgetId]
  emits via EventRelay                 rail resolves: liveWidgets[modeWidgetId] ?? regions.widgets[side]
  on a cadence + on focus              WidgetSlot renders the envelope (ready/empty/stale/unavailable)
```

Key properties:

- **`widget.data.changed` is generic**, keyed by `widgetId`, and carries the existing
  `WidgetData` envelope. There is **one** event type for all widgets — do **not** add a
  bespoke event per widget.
- **`liveWidgets` is runtime-only state that lives OUTSIDE `regions`.** A mode switch
  (`config.changed`) swaps `regions` wholesale, but `liveWidgets` is untouched, so a live
  widget survives mode switches by construction — no per-region preservation needed. (Contrast
  System Health, which predates this and uses the older `RUNTIME_OWNED_REGIONS` path in
  `bridgeStore.ts`. **New widgets use `liveWidgets`, not that path.**)
- **Rails resolve live-over-bootstrap** via `resolveWidgetData(liveWidgets, activeMode.widgets.side, regions.widgets.side)`.
  The bootstrap value is the fallback until a producer streams.
- **Producers mirror `SystemStatusPublisher`**: an actor with a fixed cadence, an immediate
  first tick, and an occlusion pause driven by dashboard visibility.

---

## 3. Code map

### Web (dashboard)
| Concern | File |
|---|---|
| Widget id registry (+ manifest mirror + lockstep test) | `apps/dashboard/src/widgets/widgets.ts`, `widgets.manifest.json`, `widgets.test.ts` |
| `WidgetData` envelope, typed payloads, `resolveWidgetData` | `apps/dashboard/src/widgets/widgetData.ts` |
| Pre-bridge fixtures (one per widget + degraded exemplars) | `apps/dashboard/src/widgets/fixtures/widgetData.fixtures.json` |
| Widget renderer + interactive dispatch | `apps/dashboard/src/shell/WidgetSlot.tsx` |
| Rails (resolve + place the slot) | `apps/dashboard/src/shell/RightRail.tsx`, `LeftRail.tsx` |
| Runtime state shape (`DashboardState.liveWidgets`) | `apps/dashboard/src/state/dashboardState.ts` |
| Event → state reducer (`widget.data.changed` case) | `apps/dashboard/src/state/bridgeStore.ts` |
| Bridge event-type union + `EVENT_TYPES` allowlist | `apps/dashboard/src/bridge/cerebralBridge.ts`, `wkWebViewCerebralBridge.ts` |
| Read-only posture (disables mutating controls) | `apps/dashboard/src/state/useUiPosture.ts` |
| Transient status line (`announce`) | `apps/dashboard/src/state/ActionStatusProvider.tsx` |

### Contracts
| Concern | File |
|---|---|
| Bridge event envelope + `type` enum (the event registry) | `packages/contracts/schemas/bridge/event.schema.json` |
| Tool I/O schemas | `packages/contracts/schemas/tools/*.schema.json` |
| Authoritative tool descriptors (fixtures copy) | `packages/contracts/fixtures/valid/tools/descriptors/*.json` |
| Generated types (do not hand-edit) | `packages/contracts/generated/typescript/contracts.ts`, `packages/contracts/Sources/CerebralContracts/GeneratedContracts.swift` |
| Regenerate | `node scripts/generate-contracts.mjs` |

### Native / core
| Concern | File |
|---|---|
| Portable domain reader (example) | `packages/core/Sources/CerebralCore/Repos/ActiveReposProvider.swift` |
| Default user-content paths (e.g. `~/Projects`) | `packages/core/Sources/CerebralCore/Workspace/WorkspacePaths.swift` |
| Envelope mapping + `widget.data.changed` factory | `packages/runtime-host/Sources/CerebralRuntimeHost/BridgeEvents.swift` |
| Bootstrap composition | `packages/runtime-host/Sources/CerebralRuntimeHost/BootstrapComposer.swift` |
| Producer actor (example) + the one it mirrors | `apps/mac/Sources/CerebralMacAdapters/ActiveReposPublisher.swift`, `SystemStatusPublisher.swift` |
| App wiring (start/pause the producers) | `apps/mac/CerebralHelm/AppBridgeRuntime.swift` |

### Tools (for a widget that triggers an action)
| Concern | File |
|---|---|
| Runtime descriptors (authoritative) | `config/tools/descriptors/*.json` |
| Stricter-only overlay | `config/tools/*.json` |
| Capability protocols | `packages/tools/Sources/CerebralTools/Adapters/NativeCapabilities.swift` |
| Capability bundle + `.mocks()` | `packages/tools/Sources/CerebralTools/Adapters/ToolCapabilities.swift` |
| Deterministic mocks | `packages/tools/Sources/CerebralTools/Adapters/Mock/MockNativeAdapters.swift` |
| Stable capability ids | `packages/tools/Sources/CerebralTools/Adapters/CapabilityMatrix.swift` |
| Portable handlers | `packages/tools/Sources/CerebralTools/Handlers/PortableToolHandlers.swift` |
| Handler↔capability wiring + step-input validation | `packages/tools/Sources/CerebralTools/PreMacToolRuntime.swift` |
| Mac adapters | `apps/mac/Sources/CerebralMacAdapters/NSWorkspaceCapabilities.swift`, `WorkspaceOpening.swift` |
| Mac composition (+ `nativeCapabilityIDs`) | `apps/mac/Sources/CerebralMacAdapters/MacToolCapabilities.swift` |
| Command grammar → tool call | `packages/core/Sources/CerebralCore/Parser/{CommandIntent,DirectCommandParser}.swift`, `Runtime/CommandRuntime.swift` |
| Typed web dispatch helper (example) | `apps/dashboard/src/shell/openProject.ts` |

---

## 4. Recipe: make a widget live

1. **Register / assign.** Ensure the widget id is in `widgets.ts` (+ manifest), and the target
   mode's `config/modes/<mode>.json` `widgets.{left,right}` references it.
2. **Domain reader (portable core).** Put the read logic in `packages/core` (Foundation only,
   **no AppKit** — it must pass `RepositoryBoundaryTests`). Return a typed, `Equatable`,
   `Sendable` model. Distinguish "unavailable" (misconfigured/unreadable) from "empty"
   (readable, nothing to show) — throw for the former, return `[]` for the latter. Unit-test
   against a temp directory (swift-testing `@Test`).
3. **Envelope mapping (runtime-host).** Add an `Encodable` envelope mirroring `WidgetData`
   (`widgetId`, `state`, `headline?`, `data?`, `freshness?`, `emptyMessage?`) plus a
   `<widget>Widget(from:now:)` mapping in `BridgeEvents.swift`. Map read-failure → `unavailable`,
   `[]` → `empty`, else `ready`. Test the mapping in `RuntimeHostTests` (portable). Reuse the
   generic `BridgeEventFactory.widgetDataChangedEvent(widgetId:widget:id:timestamp:)`.
4. **Producer actor (mac adapter).** Copy `ActiveReposPublisher` (which copies
   `SystemStatusPublisher`): cadence, immediate first tick, `setActive` occlusion pause, emit via
   `EventRelay`. Pick a cadence matched to how fast the data changes (repos = 5 s; System Health = 2 s).
   Wire it into `AppBridgeRuntime` alongside `statusPublisher` — start it in `startStatusPublishing()`
   and gate it in `setStatusPublishingActive()`.
5. **Renderer (web).** In `WidgetSlot.tsx`:
   - **Read-only widget** → add a pure `(data) => ReactNode` entry to `WIDGET_BODIES`.
   - **Interactive widget** (needs bridge / posture / status hooks) → write a dedicated
     component and dispatch to it from `WidgetBody` (see `RepositoriesBody`). Do **not** try to
     use hooks inside the static `WIDGET_BODIES` map.
   - Type the `data` slice in `widgetData.ts`.
6. **Tests + gates.** Component test in `WidgetSlot.test.tsx`; run the gates in §8.

The bootstrap seed is currently left as the honest `unavailable` stub — the producer's immediate
first tick populates the slot. A mode-aware bootstrap seed (skeleton instead of the brief flash)
is a **deferred, optional** improvement (§9); don't blanket-seed all slots or non-live widgets
will look like they're loading forever.

---

## 5. Interactive widget pattern (rows that do something)

From `RepositoriesBody` in `WidgetSlot.tsx`:

- **Rows are reset `<button class="widget-list__button">` inside the card `<li>`** — the whole
  row is the click target while keeping the card styling.
- **Dispatch through the command bus, not a bespoke bridge op.** A widget action with a dynamic
  argument goes through `submitCommand({ rawInput: "<verb> <arg>", source: "dashboard" })` — the
  same path as quick actions' `run <id>`. Wrap it in a small typed helper (e.g.
  `submitOpenProject` in `shell/openProject.ts`) so the grammar string lives in one place.
  **Only add a dedicated bridge operation if the action has a distinct result/side-effect**
  (like `captureNote`/`applyMode`); a plain receipt does not justify one.
- **Respect posture.** Disable rows when `useUiPosture().readOnly` (offline/recovery). Never
  expose a mutating control while read-only.
- **Be honest.** Surface only what the bridge actually returned via `announce(...)`; never
  fabricate success. Missing data renders honestly (e.g. a nil git branch → a muted `—`, never a
  made-up value).

### Row layout / truncation conventions (learned on `repositories`)
- Primary text + secondary chip on **one line each**; truncate with ellipsis, never wrap.
  Truncation needs `min-width: 0` on the flex child (its default `auto` blocks shrinking).
- **The primary label wins the row.** Give the secondary/right element the higher `flex-shrink`
  and a `max-width` cap so it yields space first; the name only truncates as a last resort.
- Size a short chip to its content (no `min-width` that pads short values like `main` wide);
  cap long values with `max-width` so they truncate instead of pushing the name.
- Reclaim width with fractional moves, not by widening the column: slightly smaller label font,
  tighter card padding, a small negative `margin-inline` on `.shell-right .widget-list` to nudge
  cards toward the panel edge. Keep it subtle.
- Icons: small line-SVGs, `viewBox="0 0 24 24"`, `fill="none"`, `stroke="currentColor"`,
  `stroke-width="1.6"`, round caps/joins (matches `PanelGlyph`). `aria-hidden`.
- Use design tokens (`--ch-space-*`, `--ch-font-*`, `--ch-radius-*`, `--ch-accent-primary`,
  `color-mix(...)` for accent tints) — never per-mode literals; the accent re-themes for free.

---

## 6. Adding a tool (for widget actions)

Tools are the typed, permission-aware way a widget acts on the platform. `project.open` (open a
repo path in the editor) is the reference. **Descriptors are authoritative (ADR-003);
`config/tools/*.json` may only tighten, never weaken.**

Checklist for a new tool:
1. **I/O schemas** in `packages/contracts/schemas/tools/`, then `node scripts/generate-contracts.mjs`.
2. **Descriptor** in **both** `config/tools/descriptors/<id>.json` (runtime) **and**
   `packages/contracts/fixtures/valid/tools/descriptors/<id>.json` (fixtures) — they must be
   **byte-identical**. Optional stricter-only overlay in `config/tools/<id>.json`.
3. **Capability protocol** + result type in `NativeCapabilities.swift`; a **mock** in
   `MockNativeAdapters.swift`; a slot in `ToolCapabilities` (+ default + `.mocks()`).
4. **Handler** in `PortableToolHandlers.swift`; wire it in `PreMacToolRuntime.makeRegistry` and
   add a `validateStepInput` case.
5. **Mac adapter** implementing the capability; add its id to `CapabilityMatrix.Capability`
   (+ `.all`) and to the Mac `nativeCapabilityIDs` in `MacToolCapabilities.make`.
6. **Bump the tool-set count in THREE places** (they will fail otherwise):
   `Tests/CoreModelTests/ToolRegistryTests.swift` — the `mvpToolIDs` set **and** the separate
   `registry.toolIDs.count == N` assertion — and `scripts/contracts-tool.test.mjs` `mvpToolIds`.
7. **Command grammar** (if triggered from the UI): add a `CommandIntent` case, a verb in
   `DirectCommandParser` (free-text remainder for path/text args; add to `supportedPatterns`),
   and the intent→tool mapping in `CommandRuntime`.

### Risk & confirmation (important)
- **`local_write` is NOT confirmation-gated by default** — it's one action, one click. Only
  irreversible / external-write / destructive / shell / financial classes gate, **or** when the
  user turns on the global "ask before all actions" tightening. So a widget "open / launch"
  action opens immediately; don't design a per-click confirmation for it.
- Risk classification and confirmation policy are deterministic and **outside models** — never
  bypass them for convenience.

### Registering a new bridge **event** type (4 coordinated edits)
1. Add the string to `event.schema.json`'s `type` enum.
2. `node scripts/generate-contracts.mjs` (regenerates the Swift + TS enums).
3. Add a `BridgeEventFactory.<name>Event(...)` in `BridgeEvents.swift`.
4. Add the string to `EVENT_TYPES` in `wkWebViewCerebralBridge.ts` **and** the `BridgeEventType`
   union in `cerebralBridge.ts` — **an event missing from `EVENT_TYPES` is silently dropped by
   the WKWebView bridge.** (This is the classic gotcha; always check it.)

---

## 7. Honest degraded states

Every widget renders four states via the `WidgetData` envelope; never fabricate:
- `ready` — headline + data (may accompany `stale`).
- `empty` — resolved, nothing to show — a healthy zero-result with a specific `emptyMessage`.
- `stale` — last value shown with a freshness marker (e.g. live stream dropped).
- `unavailable` — capability/data source unreachable, with an honest message.

Missing sub-fields are omitted, not invented (nil git branch → `—`, never a guessed branch).

---

## 8. Verification gates

Run what the change touched:
- **Contracts/config (Node):** `node scripts/validate-contracts.mjs`, `node scripts/check-contract-drift.mjs`,
  `node scripts/validate-config.mjs`, and the relevant `node --test scripts/contracts-*.test.mjs`.
- **Swift:** `swift build --target <Target>` for a fast compile, then `swift test` (full suite is
  ~fast here). New portable code must keep `RepositoryBoundaryTests` green.
- **Dashboard:** `pnpm --dir apps/dashboard typecheck`, `npx vitest run`, `npx eslint <files>`.

Swift gotcha: a `Result` type in the contracts module shadows `Swift.Result` — write
`Swift.Result<...>` in runtime-host/tools code.

---

## 9. Decisions log (NIC-131, and sprint-wide)

Conventions established by the blueprint — reuse unless a ticket says otherwise:

- **Live-widget delivery = generic `widget.data.changed` + `liveWidgets` map** (§2). Reusable;
  no per-widget event.
- **Producers mirror `SystemStatusPublisher`** (actor, cadence, occlusion pause, immediate first tick).
- **Widget actions dispatch via `submitCommand` grammar + a typed helper**, not a bespoke bridge
  op, unless there's a distinct result.
- **`local_write` is one-click** (not gated) — see §6.
- **New editor/path tools are their own tool** (e.g. `project.open`), keeping `app.open`'s
  "no arbitrary path by construction" invariant intact. Path is constrained to its root **in the
  adapter** (a schema can't know the root).
- **Repos = read `.git/HEAD` directly** (parse `ref: refs/heads/<branch>`, detached → short SHA;
  no process, no shell; `packed-refs` not needed for branch names).
- **Projects layout = depth-2.** `~/Projects/<project>/<repo>`: the root holds *project folders*
  (each a name + a `description.md`, not necessarily code), and repos live one level below. The
  reader scans depth 2; a project folder is never itself treated as a repo. Default root
  `~/Projects` via `WorkspacePaths.defaultProjectsRoot()`.

**Deferred / open (decide before relying on them):**
- Durable, user-editable **projects-root setting** — not built. Storage form (raw path vs a
  reference like `knowledgeRootReference`) is undecided. Readers take the root as a constructor
  param and default to `~/Projects` for now.
- **Mode-aware bootstrap widget seed** — optional polish to replace the brief pre-first-tick
  `unavailable` flash with a same-shape skeleton (needs the composer to know the active mode's
  widget assignment). Don't blanket-seed.

---

## 10. Build & relaunch the Mac app

- **Native/Swift change** → full rebuild (re-signs → you must re-grant Accessibility in System
  Settings afterward):
  ```
  apps/mac/scripts/build-dashboard-bundle.sh
  xcodebuild -project apps/mac/CerebralHelm.xcodeproj -scheme CerebralHelm \
    -configuration Debug -derivedDataPath apps/mac/build/dd build
  open apps/mac/build/dd/Build/Products/Debug/CerebralHelm.app
  ```
- **Web-only change** → skip Xcode and **preserve the Accessibility grant** by swapping just the
  bundle (the executable's signature is untouched):
  ```
  apps/mac/scripts/build-dashboard-bundle.sh
  APP=apps/mac/build/dd/Build/Products/Debug/CerebralHelm.app
  rm -rf "$APP/Contents/Resources/DashboardBundle"
  cp -R apps/mac/DashboardBundle "$APP/Contents/Resources/DashboardBundle"
  # quit + relaunch the app
  ```
  `codesign --verify` will then report "a sealed resource is missing or invalid" — that's
  expected and harmless for the Debug build (hardened runtime disabled); it still launches and
  WKWebView serves the fresh bundle.

Always quit the running instance before relaunching.

---

## 11. Keeping this current

When you finish a widget or make a reusable decision:
1. Update the roster table (§1) status.
2. Add any new pattern to §4–§7 and any decision to §9.
3. If you added a gate, count assertion, or gotcha, note it in §6/§8 so the next person doesn't
   trip on it.

_Last updated: 2026-07-22 — after NIC-131 (repositories) shipped as the blueprint._
