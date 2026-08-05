# MVP Polish — in-progress ticket plan

**Status:** Planned, nothing implemented. Baseline `01ef74a` on `dev`, working tree clean.
**Owner:** Nick Southey
**Source:** Planning session 2026-08-05
**Scope:** The ten Linear issues that were in a started state on 2026-08-05 — 16 increments total.

## Why this document exists

Ten tickets at ~16 commit-sized increments is far more than one session can supervise. This
document is the **authoritative plan and handoff**: every root cause already traced, every
owner decision already made, and every fact that was expensive to discover. Work one
increment per session, from a fresh context, without re-deriving any of it.

**Read this file first.** It outranks the Linear ticket text wherever the two disagree — several
tickets are stale or were re-scoped during planning, and the deviations are recorded here with
their reasons. Where a ticket's own acceptance criteria need editing in Linear, that is called out.

### How to use it

1. Pick the next unchecked increment from the sequence below.
2. Read that ticket's section in full — root cause, decisions, and the increment spec.
3. Read *Traps* before touching contracts or events. Every item there has already bitten someone.
4. Implement one increment. Do not roll into the next.
5. Tick the box here, note anything discovered, and hand back for review.

File:line references are as of `01ef74a` and may drift — treat them as "start looking here",
not as gospel.

---

## Sequence

| # | Ticket | Increment | Done |
|---|---|---|---|
| 1 | NIC-176 | Settings snapshot follows `settings.changed` | ☑ |
| 2 | NIC-171 | Lock the Heimlich indicator | ☑ |
| 3 | NIC-158 | Sample memory pressure + contract field | ☑ |
| 4 | NIC-158 | Smoothed load in the publisher | ☑ |
| 5 | NIC-158 | Three-tier tones + gliding bars | ☑ |
| 6 | NIC-172 | Weather replay on new surfaces | ☑ |
| 7 | NIC-175 | Nested-folder app discovery | ☑ |
| 8 | NIC-175 | `apps.changed` event + surface refresh | ☑ |
| 9 | NIC-167 | Shared search field + `ReferencePicker` | ☑ |
| 10 | NIC-167 | More Apps + pin popover | ☑ |
| 11 | NIC-115 | **Atomic engine swap** (was 11+12+13 — they cannot be split, see the blocker in the NIC-115 section) | ☐ |
| 14 | NIC-123 | Re-run the 5-slot experiment — **DONE: 10/10 green, crash gone, close the ticket** | ☑ |
| 15 | NIC-123 | ASan — **not needed; 14 was green** | ☑ n/a |
| 16 | NIC-116 | Yams on the frontmatter read path | ☑ |
| 17 | NIC-116 | Reconcile the duplicate reader | ☑ |

**NIC-177 has no increment** — it is already built and committed; see its section.

Ordering rationale: contracts before consumers; NIC-115 before NIC-123 because it removes
`swift-toolchain-sqlite`, the prime suspect in every recorded NIC-123 crash trace.

---

## Owner decisions locked in this session

Do not re-litigate these. All are Nick's calls, 2026-08-05.

| Decision | Ticket |
|---|---|
| Memory bar **fill width and % figure stay usage-based**; pressure drives **colour only**, so one bar carries the full picture | NIC-158 |
| CPU tone thresholds **60 / 85**, applied to a **time-averaged** value | NIC-158 |
| Values are **smoothed** (exponential moving average) so bars slide rather than jump, and red means *sustained* load | NIC-158 |
| Heimlich indicator is **locked to its resting state** — showing lifecycle states "makes it seem like Heimlich exists when he doesn't" | NIC-171 |
| NIC-175's reported symptom is **not a defect** (see its section); the ticket proceeds for the two real gaps found | NIC-175 |
| NIC-115: **strike the FTS5 acceptance criterion**, and do **not** adopt `DatabaseMigrator` | NIC-115 |
| NIC-116: Yams on the **read path only**; emit stays untouched | NIC-116 |
| NIC-123: **close with evidence, don't cancel** — run the experiment rather than assume | NIC-123 |

---

## Traps

Discovered the hard way, in this repo, previously. Check these before writing code.

- **A new bridge event needs SIX edits, not one.** Schema enum in
  `packages/contracts/schemas/bridge/event.schema.json` → regenerate contracts → emit site →
  `BridgeEventType` union in `apps/dashboard/src/bridge/cerebralBridge.ts` → the reducer in
  `apps/dashboard/src/state/bridgeStore.ts` → **and the `EVENT_TYPES` allowlist in
  `apps/dashboard/src/bridge/wkWebViewCerebralBridge.ts:88`**. An event missing from that
  allowlist is *silently dropped* by the WKWebView transport and works fine in the browser
  preview. This is exactly how the NIC-143 collapse icon broke. There is already a regression
  test guarding it at `wkWebViewCerebralBridge.test.ts:203` — extend it in the same commit.
- **`BridgeSession.composeBootstrapState()` is the only bootstrap composition.** Every transport
  must use it. Do not hand-compose a payload for a new window.
- **Events are fire-and-forget with no replay by default.** Anything a webview can miss between
  page load and bridge handshake needs an explicit resend. See NIC-172.
- **Ad-hoc signing invalidates TCC on every rebuild.** After any `xcodebuild`, the Accessibility
  grant is dead — remove and re-add CerebralHelm in System Settings → Privacy & Security →
  Accessibility before manual verification. Same root cause as the Keychain prompt storm.
- **Descriptors are authoritative** (ADR-003). `config/tools/*.json` is a stricter-only overlay.
- **Do not create git commits.** Nick reviews, commits, then prompts the next increment.

---

## CI flakiness — favicon warming (fixed 2026-08-05)

`core-swift-linux` went red on PR #15 with two favicon tests in `BridgeSessionTests`
(`listUrlsWarmsFaviconsAndEmits`, `addUrlReference…warms…`) — while macOS CI and local runs were
green. **Not a defect: rerunning the identical commit passed.**

Cause: those tests wait on fire-and-forget `Task {}` work (`BridgeSession.warmFavicons`), which has
no completion handle to await, so the test polls. The poll deadline was **3s**, which is not a safe
budget for the cooperative pool to schedule background work on a 2-core GitHub runner with the suite
running in parallel. Nothing about the change under test was slow — the favicon mock returns
instantly and the cache is plain file I/O. Adding tests to the suite raised contention enough to tip
an already-thin budget.

Fixed by raising the shared `waitUntil` default to **30s**, with the reasoning recorded at the
helper. This weakens no assertion — the caller still fails if the condition never holds — and costs
nothing on a green run, since it returns the moment the condition is true; the deadline only elapses
when the test was going to fail anyway.

**Ruled out** (checked, not assumed): Yams builds cleanly on Linux — it vendors libyaml, so unlike
GRDB it needs no system package and no CI provisioning. The previously recorded
`ProcessHookCapability` cooperative-pool starvation does not apply here either: that adapter is
`#if canImport(AppKit)`-gated, so it compiles to nothing on Linux.

**Known remaining pattern:** the `MacAdapterTests` publishers each have their own `waitUntil` with
2–3s deadlines. They run only on the macOS job, which is less contended and has stayed green, so
they were left alone — but they are the same shape and the same fix applies if they ever flake.

## Verification on this Mac

```bash
swift test
```

```bash
corepack pnpm --dir apps/dashboard test --run
```

- `node scripts/test.mjs` (the repo runner) **cannot run on this Mac** — `corepack` is missing.
  Pre-existing, unrelated to this work. Use the two commands above directly.
- Contract work additionally needs `node scripts/validate-contracts.mjs` and
  `node scripts/check-contract-drift.mjs`.
- Playwright visual snapshots are `-win32` and will not match here. Do not regenerate them.
- Keychain tests are opt-in and must be isolated:
  `CEREBRAL_KEYCHAIN_TESTS=1 swift test --filter MacAdapterTests`.
- **Never drive the app with synthetic input to verify.** Run the gates, then hand Nick a manual
  verification list.

---

# NIC-176 — Fix mode-calendar selection

**Root cause: confirmed. Pure UI-state bug — the entire write path is correct.**

Verified working end to end: TS validator (`settingsPatch.ts:213`), Swift validator
(`SettingsPatchValidator.swift:132`), `SettingsChanges` → `calendarModeMapJSON`
(`SettingsStore.swift:171`), SQLite column + migration `0012_calendar_mode_map`, and the
`calendarModeMap` property on `settings-snapshot.schema.json`.

The defect: `SettingsSnapshotProvider` (`apps/dashboard/src/shell/settings/SettingsSnapshotProvider.tsx:28`)
reads `bridge.getSettings()` **once on mount and never again**. `CalendarModeMapField`'s `<select>`
is fully controlled by `snapshot.calendarModeMap` with no local state
(`SettingsPanels.tsx:1244`), so after `assign()` writes, React re-renders from the *unchanged*
snapshot and the box reverts.

Everything needed already exists: `updateSettings` emits `settings.changed` carrying the **full
resolved snapshot** (`BridgeSession.swift:2909`), the event is in the schema enum and in the
`EVENT_TYPES` allowlist (`wkWebViewCerebralBridge.ts:94`), and the coordinator delivers it to the
settings window (`WindowCoordinator.swift:232`). Nobody subscribes.

### Increment 1 — Settings snapshot follows `settings.changed`

- **Goal:** any settings control rendered straight off the snapshot reflects its own write.
- **Changes:** in `SettingsSnapshotProvider`, add a `bridge.subscribe` for `settings.changed` that
  replaces state with `event.payload.settings`; keep the initial `getSettings()` read; unsubscribe
  on unmount. `CalendarModeMapField` itself is not touched.
- **Files:** `apps/dashboard/src/shell/settings/SettingsSnapshotProvider.tsx`,
  `SettingsOverlay.test.tsx` (existing calendar-map coverage at line 478), new provider test.
- **Contracts:** none.
- **Tests:** emitting `settings.changed` updates the provider; the calendar `<select>` holds the new
  mode after `assign`; a malformed payload is **ignored rather than clearing** the snapshot — match
  the existing guard style in the `mail.changed` / `schedule.changed` reducer cases.
- **Done when:** picking a mode in Settings → Setup → Calendar leaves the dropdown on that mode and
  it survives a settings-window reopen.
- **Deferred:** no optimistic local state; the round trip is local and sub-frame.

**BUILT 2026-08-05** on `mvp-polish/micro-features-and-tech-debt`. Gates: dashboard 559 tests
green, `tsc --noEmit` clean, eslint clean. No Swift touched.

One thing the plan didn't anticipate, now handled: an event can land **while the initial
`getSettings()` read is still in flight**, in which case the slower read resolves with pre-write
values and would clobber the newer snapshot. The provider tracks a `superseded` flag so the first
live event wins over both a late resolve and a late rejection. Two tests cover it.

Verified the regression guard genuinely bites: reverting only the provider makes the extended
calendar test fail with `expected 'executive' to be 'developer'`.

> First in the sequence because it fixes this class of staleness for *every* snapshot-backed
> control, not just the calendar dropdown.

---

# NIC-171 — Heimlich icon stuck on "Done"

**Root cause: confirmed.**

`LIFECYCLE_TO_HEIMLICH` maps `succeeded → success` (`bridgeStore.ts:148`), and `success` is
terminal — nothing returns it to `idle`. `success` renders "Done" (`labels.ts:12`). `failed → error`
is equally sticky. The only reset is a `config.changed` mode switch, which swaps the whole
`heimlich` object from bootstrap — which is why it's "sometimes".

**Owner decision:** lock it. There is no assistant runtime, and surfacing lifecycle states
"makes it seem like Heimlich exists when he doesn't". NIC-124 already made the resting state read
"Not implemented".

### Increment 1 — Lock the Heimlich indicator

- **Goal:** the indicator stops reporting a lifecycle it doesn't own, and cannot stick.
- **Changes:** stop folding `command.lifecycle.transition` into `state.heimlich` in the reducer.
  **Keep the `activeWorkflowRun` clearing in that same case** — it is separate and correct (NIC-85).
  Remove `LIFECYCLE_TO_HEIMLICH` rather than leaving it orphaned. Bootstrap's `idleHeimlich()`
  becomes the single source.
- **Files:** `apps/dashboard/src/state/bridgeStore.ts`, `bridgeStore.test.ts`,
  `apps/dashboard/src/shell/labels.ts` (**the comment at line 5 becomes wrong and must be corrected**).
- **Contracts:** none. `DashboardHeimlichState` keeps every case for when the assistant lands.
- **Tests:** a succeeded lifecycle leaves `heimlich.state === "idle"`; a terminal transition still
  clears `activeWorkflowRun`.
- **Done when:** running quick actions repeatedly never leaves the indicator on "Done".

**BUILT 2026-08-05.** Gates: dashboard 560 tests green, `tsc --noEmit` clean, eslint clean on all
of `src/`. No Swift touched — the native `BootstrapComposer` already only ever composes
`idleHeimlich()`, so the lifecycle mapping in the web reducer was the sole writer of a non-idle
state. The `command.lifecycle.transition` case now clears `activeWorkflowRun` and nothing else.

Three stale comments were corrected alongside it — they each asserted the old behaviour:
`labels.ts:5`, `PersistentBottomBar.tsx:242` (the status-dot map claimed it "only lights up while
a command runs"), and the reducer case itself.

Two existing tests asserted the removed behaviour and were **reversed with the reasoning recorded
in the test body**, per repo precedent:
- `bridgeStore.test.ts` "maps command-lifecycle status onto Heimlich state" → now
  "never drives Heimlich state from the command lifecycle", looping every status.
- `createBridgeStore` "seeds from initial state and folds the bridge event stream" used a lifecycle
  event as its proof that the stream folds and notifies. Since a lifecycle event now moves no state,
  it can no longer serve that purpose — switched to `weather.changed`, and it additionally asserts a
  lifecycle event notifies **no** subscriber.

**Left deliberately in place:** the unreachable non-idle entries in `HEIMLICH_STATE_LABELS` and
`HEIMLICH_STATE_DOT`, and every case of the `DashboardHeimlichState` contract enum — they are the
reference renderings for when a real assistant lands. `fixtures/catalog/canonical-states.json` still
carries `error` / `offline` / `thinking` heimlich states for the same reason; those are
design-preview fixtures and are never produced by the runtime.

---

# NIC-158 — Colour-code memory by load

**Current state.** `usageTone()` is two-valued — mode accent below 90%, `danger` above
(`SystemHealthPanel.tsx:16`) — while `batteryTone()` is already the three-tier shape. The CSS tones
`.metric-bar__fill[data-tone="good"|"warning"|"danger"]` **already exist** (`shell.css:1602`), so the
web side is a pure function change plus transitions.

Memory percent is `usedBytes/totalBytes` where `used` mirrors Activity Monitor's "Memory Used"
(`MacSystemStatusCapability.swift:329`). On a modern Mac that sits near 100% permanently — the
"appearing super full all the time" complaint. macOS's own pressure level is not sampled anywhere.

### Verified facts

- **`sysctl kern.memorystatus_vm_pressure_level` reads `1` on this machine.** Same values the
  public dispatch memory-pressure source reports: `1` normal, `2` warn, `4` critical. Poll-shaped,
  so it fits the existing `SystemMetricSampling` seam. It is an *undocumented* sysctl — treat any
  unexpected value as `nil` and fall back to percentage tones, so a future OS change degrades
  honestly rather than lying.
- `vm.memory_pressure` also exists and reads `0`. It is **not** the dispatch level. Don't use it.
- **`SystemStatusPublisher` samples every 2 seconds with no smoothing** (`SystemStatusPublisher.swift:29`).
- **This machine:** M5 Pro, 18 logical cores (`hw.perflevel0.name` = Super ×6,
  `perflevel1.name` = Performance ×12 — no traditional efficiency cores on this part).

### Why smoothing, and what it buys

CPU percentage is the fraction of *total machine capacity* busy in the sample window. Because it
is normalised across all cores, one pegged core reads ≈5.6% here but ≈12.5% on an 8-core Air —
the thresholds are inherently machine-relative and there is no absolute "70% is bad on a Mac".

What matters to the user — heat, fan, battery, responsiveness — is the **area under the curve over
time**, not the peak. A 2-second burst at 100% costs nothing; two minutes at 80% spins the fan.
An exponential moving average measures exactly that, which means **one mechanism delivers both**
things asked for: the bar slides instead of jumping, *and* red requires sustained load by
construction.

Behaviour at a ~30s time constant, 2s samples, from a 10% idle baseline:

| Situation | Result |
|---|---|
| One 2s spike to 100% | 10% → ~16%, settles back. Never yellow. |
| Sustained 100% | yellow (60) at **~24s**, red (85) at **~54s** |
| Spiking 100% half the time | converges ~55% → yellow, stays yellow |
| Load stops after red | below yellow in ~12s, near idle in ~40s |

Frequent spiking *does* accumulate, and that is correct — thermally, "100% half the time" and
"steady 50%" are the same thing.

**Memory gets a much lighter average (~10s)** purely so the bar glides; usage percentage is already
stable. The **pressure level is passed through unfiltered** — the kernel already debounces it, and
double-filtering a value someone else smoothed is how indicators start lying.

### Honesty rules (non-negotiable)

- **Never coast.** A failed sample sets the channel `unavailable`; the average does not drift on.
- **Never ramp from zero.** Seed the average from the first real sample, so launch doesn't show a
  fake low reading climbing up.
- **Say what it is.** Update the `cpuPercent` schema *description* to state it is time-averaged,
  and put a tooltip on the row. Nothing downstream should assume it's instantaneous.

### Where the smoothing lives

**In the publisher, not the capability.** `SystemStatusPublisher` owns the cadence, so a
cadence-dependent filter belongs with it, and every surface then receives the identical smoothed
stream instead of computing its own drifting copy. The one-shot `system.status.read` tool keeps
going through `MacSystemStatusCapability.readMetrics` and stays **instantaneous and honest** —
that is what a tool contract should report.

Composes with NIC-172: a companion attaching mid-session picks up the current smoothed value
through that replay, so it doesn't start from a cold average.

### Increment 1 — Sample memory pressure, carry it on the contract

- **Goal:** the payload carries an honest macOS pressure level alongside the existing percent.
- **Changes:** add `func memoryPressure() -> MemoryPressureLevel?` to `SystemMetricSampling`;
  implement in `LiveSystemMetricSource` via `sysctlbyname("kern.memorystatus_vm_pressure_level")`,
  mapping 1/2/4 → normal/warn/critical and anything else → `nil`; carry it on the memory channel;
  add `memoryPressure` as an **optional** enum property on `DashboardSystemHealthRegion`
  (`bootstrap-state.schema.json:200`); regenerate contracts; map it in `BridgeEvents` /
  `SystemStatusPublisher`.
- **Files:** `MacSystemStatusCapability.swift`, `SystemStatusPublisher.swift`,
  `packages/contracts/schemas/bridge/bootstrap-state.schema.json`, generated TS/Swift,
  `packages/tools/.../Mock/MockNativeAdapters.swift`, `Tests/MacAdapterTests/`.
- **Contracts:** additive optional field → no migration, older payloads stay valid.
- **Tests:** scripted samples per level; unsamplable → `nil`; contract drift check.
- **Done when:** `system.status.changed` carries `memoryPressure` on the Mac host. Nothing renders it yet.

**BUILT 2026-08-05.** Gates: `swift test` **1378** green · dashboard **561** green · `tsc`/eslint
clean · validate-contracts, check-contract-drift, validate-config clean · **xcodebuild BUILD
SUCCEEDED** (the app target was worth building — this increment edits `BootstrapComposer`).

Shape decisions made while building, for increments 2–3 to build on:

- **`SystemStatusMemoryChannel` is a new dedicated channel type**, not a field bolted onto the
  shared `SystemStatusChannel` (which cpu/display still use). Memory now mirrors how network and
  battery already have their own channel types. Same on the wire:
  `BridgeEventFactory.SystemMetricsMemoryChannel`.
- **Pressure is independent of `availability`.** `availability`/`value` describe the *percentage*
  only; a host can report a level with no percentage or vice versa. Deliberately mirrors NIC-156's
  `wifiPower`-vs-link-rate split, and the reducer does not gate `memoryPressure` on `memoryLive`.
- **`MemoryPressureLevel` is a local raw-value enum in the adapter**, mapped to the contract string
  at the publisher (`.rawValue`) — the `WiFiPower` pattern, not a dependency on generated contracts.
- **The portable tool contract is unchanged.** `readMetrics(.memory)` still returns the percentage
  only; pressure rides the streaming snapshot alone. There is a test asserting this.
- **Unrecognized sysctl values map to `nil`, not to the nearest level.** A future OS adding a state
  must degrade to "we don't know" so the bar falls back to the percentage, never to a confident
  `normal` that claims the machine is fine on no evidence. Asserted at the adapter, the publisher
  (level omitted from the JSON), and the reducer (unknown string → `undefined`).

`SystemMetricSampling` gained a requirement with **no default implementation** — three test doubles
(`FakeMetricSource`, `SteadySource`, `SuiteMetricSource`) implement it explicitly, plus a new
`PressurelessSource` for the degradation path. A protocol-extension default returning `nil` was
rejected: it would let a real source silently never implement the seam.

### Increment 2 — Smoothed load in the publisher

- **Goal:** streamed CPU and memory values move gradually and encode sustained load.
- **Changes:** exponential moving average in `SystemStatusPublisher` — **~30s** time constant for
  CPU, **~10s** for memory; seeded from the first real sample; **reset (not coasted)** when a
  channel reports unavailable. Update the `cpuPercent` schema description. Pressure passes through
  unfiltered.
  Formula: `smoothed += α × (sample − smoothed)`, `α = 1 − exp(−Δt/τ)`; at Δt=2s, τ=30s → α ≈ 0.065.
- **Files:** `SystemStatusPublisher.swift`, `bootstrap-state.schema.json` (description only),
  `Tests/MacAdapterTests/`.
- **Tests:** a single spike stays below the yellow threshold; sustained load crosses yellow and red
  at the expected sample counts; a 50% duty cycle converges near 50%; an unavailable sample resets
  rather than coasting; the first sample is not averaged against zero.
- **Done when:** the streamed value climbs and falls smoothly and cannot be pushed red by a transient.
- **Depends on:** Increment 1.

**BUILT 2026-08-05.** Gates: `swift test` **1389** green · dashboard **561** green · `tsc`/eslint
clean · drift + config validators clean · **xcodebuild BUILD SUCCEEDED**.

What increment 3 (the web side) needs to know:

- **The math lives in `ExponentialMovingAverage`** (new file in `CerebralMacAdapters`), a pure value
  type with its own 7 tests at the real 30 s constant. The publisher owns two instances and applies
  them in `smoothed(_:)`; `payload(_:)` stays a pure unsmoothed mapping, so the existing payload
  test was unaffected.
- **Weighting is by elapsed time, not sample count** — using each channel's own `sampledAt`, so no
  new clock seam was needed and the tests are fully deterministic. A late tick or a long gap
  weights correctly instead of counting as one uniform step.
- **The plan's three honesty rules are each pinned by a test:** seeds from the first real sample
  (no ramp from zero); resets rather than coasts when a channel is unavailable/loading; and
  `setActive(false)` also resets, because nothing is sampled while the dashboard is hidden so
  there is no history to continue.
- **Smoothing replaces the value and nothing else** — availability, `sampledAt`, and memory's
  pressure level pass through untouched, and network/battery/display are not averaged at all
  (point-in-time facts). Asserted.
- **Schema descriptions updated** for `cpuPercent` (states it is ~30 s time-averaged, and that the
  value is normalized across all logical cores) and `memoryPercent` (~10 s, and that it is *not* a
  strain signal — read `memoryPressure` for that). Doc-only; no shape change.

`SystemStatusPublisherTests` now uses `@testable import CerebralMacAdapters` so the internal
`smoothed(_:)` and the channels' internal memberwise inits can be driven at exact timestamps.
Widening either to `public` purely for tests was rejected — nothing ships against that seam.

**Measured behaviour** (2 s cadence, 10% idle baseline, τ = 30 s): one 2 s spike to 100% moves the
bar to ~15.8 and decays back; sustained 100% crosses yellow (60) between 20–30 s and red (85)
between 50–60 s; a 50% duty cycle converges within 12 points of a steady 50%.

### Increment 3 — Three-tier tones and gliding bars

- **Goal:** the panel reads as a sliding indicator with meaningful colour.
- **Changes:** replace `usageTone` with `cpuTone(percent)` (**60 / 85**) and
  `memoryTone(pressure, percent)` — **pressure wins; the percentage is the fallback** when pressure
  is absent (non-Mac host, sampling failure). Add `transition: width 1800ms linear` and a ~600ms
  colour transition to `.metric-bar__fill`. Suppress the transition on the skeleton→ready handoff so
  the bar doesn't animate up from zero on first paint. Tooltip on the CPU row.
- **Files:** `SystemHealthPanel.tsx`, `shell.css`, `DashboardShell.test.tsx`.
- **Why linear, not eased:** with an easing curve the bar decelerates into every sample and reads as
  pulse-stop-pulse. Linear at roughly the sample interval means each transition hands off to the
  next and it reads as continuous motion.
- **Displayed number:** just render the averaged value. It moves a few points per sample, so it
  reads as counting. No separate number animation.
- **Reduced motion: already handled.** `app.css:316-334` has a global safety net zeroing every
  `transition-duration`, from both the OS media query and the in-app setting. New transitions
  inherit it for free — **no extra work, do not add a bespoke guard.**
- **Tests:** per tone tier for both metrics; the no-pressure fallback path; no transition applied on
  the initial ready transition.
- **Depends on:** Increments 1 and 2.

**BUILT 2026-08-05 — NIC-158 is now feature-complete.** Gates: dashboard **565** green ·
`tsc`/eslint clean · browser-verified live (see below). No Swift touched.

- **The planned first-paint suppression was NOT needed and was deliberately not written.** Measured
  in the browser: on mount the bar paints at its real value with **zero** running animations. CSS
  transitions do not fire on initial render, and the skeleton→ready swap replaces the element
  entirely (a new node, so again no transition). Speculative suppression code would have been dead.
- **Memory's no-pressure fallback is `accent`, not a green/yellow/red guess.** Off the macOS host we
  do not know whether memory is under strain, so the bar makes no claim: it keeps the mode accent and
  retains the pre-existing 90% danger rule. Thresholding the percentage into tiers there would
  reproduce the exact bug this ticket fixes, since a healthy Mac sits near 100%.
- **Two new motion tokens**, not hardcoded durations: `--ch-motion-sampled: 1800ms` (roughly the
  sampling interval, so each transition hands off to the next) and `--ch-ease-linear`. Both are
  collapsed in the `prefers-reduced-motion` block in `tokens.css` alongside the existing durations.
- **Linear easing is load-bearing.** At 1.8s an easing curve decelerates into every sample and reads
  as pulse-stop-pulse. Verified linear in the browser: from 83.8px toward 27.9px, at 500 ms it read
  68.4px where linear predicts 68.3px.
- Reduced motion verified live: `transition-duration` collapses `1.8s, 0.2s` → `1e-05s` under
  `[data-reduced-motion="true"]`, via the existing global safety net. No bespoke guard added.

**Deliberately deferred — worth a follow-up:** `fixtures/catalog/canonical-states.json` has 8
`memoryPercent` entries and no `memoryPressure`, so the browser preview and the design reference
always render memory on the accent fallback rather than the green/yellow/red the real Mac shows.
Adding it would change the Playwright visual baselines, which are `-win32` and cannot be regenerated
on this Mac — landing that here would leave CI red for someone else. Separate, deliberate change.

**Also noticed, unrelated and untouched:** the browser console logs a React "unique key prop"
warning from `ProjectsBody` on every render. Pre-existing, not caused by this work.

**If it feels wrong in use:** the time constant is a single number. Lower τ = more responsive,
more flicker. Higher τ = calmer, laggier.

---

# NIC-172 — Weather unavailable on the second monitor

**Root cause: confirmed.**

Weather is **not in the bootstrap** — `BootstrapComposer` composes `weather: nil`
(`BootstrapComposer.swift:107`) — it arrives only as `weather.changed` on a **15-minute** cadence
(`WeatherPublisher.swift:31`).

On hot-plug, `reconcileBackdrops` builds a brand-new companion `DashboardWindowController` whose
`onBridgeReady` replays **only** `lastTopologyJSON` (`WindowCoordinator.swift:301`). The general
replay hook `resendLiveWidgetState()` resends **only news** (`AppBridgeRuntime.swift:755`) and is
wired solely to `onDashboardBridgeReady` — the primary dashboard. So the new companion holds the
empty bootstrap weather until the next tick, while the laptop keeps the value it already received.

### Increment 1 — Replay the last weather sample to any surface that comes up

- **Goal:** a companion created mid-session shows the same weather as the main display.
- **Changes:** cache the last emitted `weather.changed` JSON in `WeatherPublisher` and add
  `resend()` — **mirror `NewsPublisher.resend()`, the established pattern**. Call it from
  `resendLiveWidgetState()`. Wire the secondary's `onBridgeReady` to invoke `resendLiveWidgetState()`
  in addition to the topology replay.
- **Files:** `WeatherPublisher.swift`, `AppBridgeRuntime.swift`, `WindowCoordinator.swift`,
  `Tests/MacAdapterTests/`.
- **Contracts:** none.
- **Tests:** `resend()` re-emits the cached channel without a new fetch, and is a no-op before the
  first tick; a new companion's bridge-ready triggers the replay.
- **Done when:** plugging in a second display with weather already showing on the laptop shows the
  same reading on the companion, not "unavailable".
- **Side effect (intended):** news has the same hole on companions today — routing secondaries
  through `resendLiveWidgetState()` fixes that too.
- **Deferred → next logical increment:** a general per-surface replay registry covering *every*
  event-only widget. Right long-term shape, bigger refactor.

**BUILT 2026-08-05 — NIC-172 complete pending Nick's hot-plug verification.** Gates: `swift test`
**1392** green · **xcodebuild BUILD SUCCEEDED**. Dashboard untouched (pure native change).

- `WeatherPublisher` caches the last emitted event **JSON verbatim** and `resend()` replays it, so a
  companion sees byte-identical state to every other surface. Mirrors `NewsPublisher.resend()`.
- **`onDashboardBridgeReady` now fires for companions too**, not just the main dashboard. That is the
  actual fix: the hook already existed but was wired only to the first surface, and a companion is
  built fresh on hot-plug long after the events were sent. Its doc comment was reworded — the old
  one described a main-dashboard-only contract that is no longer true.
- Replays are served from producer caches, so firing the hook per surface **costs no fetch** — proven
  by a counting provider in the tests, not assumed.
- `resend()` before the first tick emits **nothing**. Synthesizing an "unavailable" would flash a
  wrong state ahead of the real reading (FR-SAF-07).
- The honest `unavailable` states replay too, not just good readings — a companion must learn that
  Location is denied as reliably as it learns the temperature, or it looks like a load that hung.
- **Side effect, intended:** news gets the same fix on companions, since both now route through
  `resendLiveWidgetState()`.

**No automated coverage of the coordinator wiring** — `WindowCoordinator` lives in the Xcode-only app
target, not in any SwiftPM test target, so the `onBridgeReady` → `onDashboardBridgeReady` hop is
verified by the manual hot-plug check only. The publisher half is fully unit-tested.

Test-authoring gotcha for later increments: `NSLock.lock()` **cannot be called inside an async
function** (`unavailable from asynchronous contexts`). Wrap the mutation in a synchronous private
helper, the shape `BridgeSession.stampAppDiscovery` already uses.

---

# NIC-175 — Newly downloaded apps aren't visible

**The reported symptom is not a defect.** Nick installed Steam, tried to pin it immediately, and it
appeared "after a little while". Mechanism: discovery calls `Bundle(url: entry)?.bundleIdentifier`
and **skips any entry where that fails** (`MacAppDiscoveryCapability.swift:51`). While a large app
is still copying into `/Applications`, the `.app` directory exists but its `Info.plist` isn't fully
written, so the bundle won't load and the app is correctly skipped. Steam is big; the wait was the
copy. Listing a half-copied bundle would be worse.

**Ruled out by inspection** — do not go looking again: all four surfaces call `bridge.listApps()`
(`MoreAppsPicker.tsx:58`, `PinPopover.tsx:101`, `ReferencePicker.tsx:64`, `QuickApps.tsx:123`);
`listApps` → `discoverAndMintApps()` runs a **fresh scan and mint on every call with no TTL**
(`BridgeSession.swift:1708` — the 15-minute TTL guards only the suggestion path);
`UserAppReferences.mint` is idempotent; `MoreAppsWindowController` is **rebuilt on every open**
(`WindowCoordinator.swift:498`); the `apps.list` handler and capability hold no cache.

**Two real gaps remain, and the ticket proceeds for these:**

### Increment 1 — Nested-folder app discovery

`MacAppDiscoveryCapability.enumerate` reads only **top-level** `.app` entries of `/Applications`,
`~/Applications`, `/System/Applications` (`MacAppDiscoveryCapability.swift:49`). Anything in a
subfolder — `/Applications/Utilities`, vendor folders — is invisible **permanently**, restart or not.

- **Changes:** bounded-depth enumeration. Do **not** descend into `.app` bundles. Cap depth at 2–3.
  Keep the existing 500-app cap and honest `truncated` flag.
- **Files:** `MacAppDiscoveryCapability.swift`, `Tests/MacAdapterTests/`.
- **Tests:** temp-directory fixture with a nested app; an app inside another app's bundle (must
  **not** be listed); the truncation cap.
- **Watch:** `listApps` scans on every picker open — sanity-check timing with a large vendor tree.
- **Done when:** an app in `/Applications/Utilities` appears in More Apps.

**BUILT 2026-08-05.** Gates: `swift test` **1398** green · **xcodebuild BUILD SUCCEEDED**. Dashboard
untouched.

**Measured payoff on this machine: 63 → 81 apps.** `/System/Applications/Utilities` alone holds ~56
apps — Terminal, Activity Monitor, Console, Disk Utility — every one of which was permanently
undiscoverable, so it could be neither opened by id nor pinned. The live test now asserts
`com.apple.Terminal` and `com.apple.ActivityMonitor` are found, which is a real macOS invariant
rather than a fixture.

**Measured cost: 63 ms cold, 4–5 ms warm** for the full no-icon scan (probed, then the probe was
deleted). `listApps` runs on every picker open, so this was worth measuring rather than assuming;
`maxSearchDepth = 2` is a responsiveness guarantee, not just a safety net.

- **Never descend into an `.app`** is the one rule that matters — bundles are directories, and every
  browser and IDE ships helper apps in `Contents`. Listing them would bury the real apps and mint
  junk references for things a user never launches. Covered by a test.
- An unreadable subdirectory contributes nothing rather than aborting the scan; one permission error
  must not cost the user every other app. Covered by a test that chmods a directory to `0o000`.
- **The half-copied-bundle behaviour is now pinned by a test** — a `.app` whose `Info.plist` has not
  landed yet is skipped, because `Bundle(url:)` cannot load it. This is the mechanism behind the
  Steam report (see this ticket's header); it is correct, and the test stops someone "fixing" it
  into listing unopenable entries.

The pre-existing tests only exercised the live host, so this added the first fixture-based coverage
for discovery (`makeApp` writes a minimal real bundle into a temp dir).

### Increment 2 — `apps.changed` event so open surfaces refresh

`ApplicationsFolderObserver` re-mints and calls `runtime.updateReferences`
(`AppBridgeRuntime.swift:673`) but **emits no bridge event**. No already-open surface refreshes, and
`QuickApps` joins discovery exactly once per dashboard load. This is the more valuable half — it
turns the Steam experience from "wait, close, reopen" into "it appears" once the copy settles
(1.5s debounce).

- **Changes:** add `apps.changed` to `event.schema.json`; regenerate; emit from the observer's
  reload closure; **add to the `EVENT_TYPES` allowlist** (see *Traps* — six edits, not one); have
  the three pickers and `QuickApps` re-run `listApps()` on it, following the existing
  `mode.quickapps.changed` refresh pattern already in `QuickApps.tsx:171`.
- **Files:** contracts + generated, `AppBridgeRuntime.swift`, `wkWebViewCerebralBridge.ts`,
  `cerebralBridge.ts`, `mockCerebralBridge.ts`, `MoreAppsPicker.tsx`, `PinPopover.tsx`,
  `ReferencePicker.tsx`, `QuickApps.tsx`.
- **Tests:** extend the `wkWebViewCerebralBridge.test.ts:203` allowlist regression; each surface
  refreshes on the event; contract validation.
- **Done when:** with More Apps open, dragging an app into `/Applications` makes it appear within
  ~1.5s of the copy finishing.
- **Depends on:** Increment 1.

**BUILT 2026-08-05 — NIC-175 feature-complete.** Gates: `swift test` **1398** green · dashboard
**572** green (49 files) · `tsc`/eslint clean · contract validators clean · **xcodebuild BUILD
SUCCEEDED**.

**The `EVENT_TYPES` trap is now structurally closed.** The regression test at
`wkWebViewCerebralBridge.test.ts` used to enumerate four event types by hand — so adding a fifth to
the schema and forgetting the allowlist still went green, which is exactly the failure it existed to
prevent. It now derives from the generated `CerebralHelmBridgeEventType` enum and replays **every**
contract event through the gate. Verified it bites: removing `apps.changed` from the allowlist fails
with a clear diff. **Future increments adding an event no longer need to remember this step** —
though the other five edits in the checklist still apply.

- **`apps.changed` carries no payload, by design.** Every consumer already has `listApps`, which
  re-scans and re-mints per call, and the discovery result is large (names + base64 icons for every
  app). Shipping that to every surface on every install — including surfaces with no app list open —
  would be pure waste. It is a signal, not a snapshot.
- **One shared `useDiscoveredApps` hook** replaced four near-identical mount-time fetches
  (`MoreAppsPicker`, `PinPopover`, `ReferencePicker`, `QuickApps`). Less total change than four
  duplicated subscriptions, and a future app-list surface gets the refresh by construction. Its
  `enabled` parameter serves the quick-app tiles, which gate on the discovery capability.
- The hook ignores unrelated events — discovery is a filesystem scan on every call, so re-reading on
  general bridge traffic would be a real cost. Covered by a test.
- A failed read reports honestly and **recovers on the next event** rather than latching.

---

# NIC-167 — Search bar on the app-list windows

The ticket names four surfaces; they are backed by **three** components:

| Surface | Component |
|---|---|
| More Apps | `MoreAppsPicker.tsx` |
| quickApps pinning | `PinPopover.tsx` |
| Layout Mode hot-swap | `LayoutPinPicker` → **`ReferencePicker.tsx`** |
| Layout Mode editor | `LayoutEditor` → **`ReferencePicker.tsx`** |

So `ReferencePicker` covers two of the four. House convention for filtering is plain
case-insensitive substring matching (`InputRegion.tsx:959`, `searchNotes.ts:50`) — **no fuzzy
scoring**. That also matches the NIC-168 owner decision (lexical, not semantic).

### Increment 1 — Shared search field + the two `ReferencePicker` surfaces

- **Changes:** new `PickerSearchField` component + a `filterApps(apps, query)` helper (match on
  `name`, fall back to `bundleId`); wire into `ReferencePicker`, autofocused; Escape still closes
  the dialog; empty result renders an honest "No matches" note rather than a blank list.
- **Files:** new `apps/dashboard/src/shell/PickerSearchField.tsx`, new
  `apps/dashboard/src/shell/filterApps.ts`, `ReferencePicker.tsx`, `shell.css`, new tests.
- **Contracts:** none — client-side filtering of an already-fetched list.
- **Tests:** `filterApps` case-insensitivity, bundle-id match, empty query = identity; typing
  narrows and clearing restores.

**BUILT 2026-08-05.** Gates: dashboard **584** green (51 files) · `tsc`/eslint clean ·
browser-verified live on `?surface=layoutpin`. No Swift touched.

Reusable pieces increment 10 should just wire up, not re-invent:

- **`filterApps(apps, query)`** — trimmed, case-insensitive substring on name, falling back to
  bundle id (so `com.apple` works). Empty query returns the array **by reference** (identity), so
  callers pass raw input with no special-casing. Ordering is preserved deliberately: discovery
  already sorted alphabetically and a filter is not the place to re-rank.
- **`PickerSearchField`** — autofocusing `type="search"` input. It deliberately does **not** handle
  Escape: that belongs to the dialog, and swallowing it would break "Escape closes the picker" once
  the field holds focus. There is a regression test for exactly that.
- **`.pin-pop__field--search`** CSS modifier: the base `.pin-pop__field` is sized for the URL form's
  flex row (`flex: 1 1 auto`), which is inert in a block section — the modifier makes it span the
  section, and recolors the WebKit clear button, which is otherwise near-invisible on this surface.

**Focus decision:** the search field takes mount focus, replacing `ReferencePicker`'s previous
`cardRef.focus()`. Two autofocus effects would have raced (child effects run before parent, so the
card won and the field never held focus). Escape still works because keydown bubbles from the input
to the card's handler.

**Empty states are distinguished:** "No applications match “zzz”." vs "No applications found."
Collapsing them would blame the query for an empty inventory.

Verified in the browser rather than only in jsdom: field autofocuses, spans the section, filters
live on name (`ter` → Terminal) and on bundle id (`com.apple` → Safari/Mail/Terminal), shows the
honest note at zero matches, and restores the full list when cleared.

### Increment 2 — More Apps and the pin popover

- **Changes:** wire `PickerSearchField` + `filterApps` into `MoreAppsPicker` and into
  `PinPopover`'s Applications section (`PinPopover.tsx:380`).
- **Decision:** in `PinPopover` the query filters **the Applications list only**; the Chrome-profiles
  section above it stays unfiltered — it's a short fixed list and hiding it on a query would
  surprise. Easy to reverse.
- **Depends on:** Increment 1.

**BUILT 2026-08-05 — NIC-167 feature-complete; all four surfaces filter.** Gates: dashboard **593**
green (53 files) · `tsc`/eslint clean. No Swift touched.

- Both surfaces reuse `PickerSearchField` + `filterApps` unchanged — no new filtering logic.
- `MoreAppsPicker` needed its own `.apps-picker__search` class rather than the `pin-pop` one: its
  layout is a flex column with a scrolling tile grid, so the field is `flex: 0 0 auto` to stay
  pinned between the header and the grid instead of scrolling away with the tiles. Verified live
  (`searchTop` 43 vs `gridTop` 62).
- Mount focus moved to the search field on both, replacing their `dialogRef`/`cardRef` focus — the
  same trade as increment 9, with Escape still bubbling. Both have a regression test for Escape.
- The Chrome-profiles-stay-unfiltered decision is now **pinned by a test**, not just a comment.

**`PinPopover` cannot be browser-verified.** Its quick-app slots are disabled off the macOS host
(gated on `native.apps.list`), so the popover never opens in the preview — the slots render as
"App discovery is available on the macOS host". Covered by 4 jsdom tests instead, and the two
shared components it uses were verified live through `ReferencePicker` and `MoreAppsPicker`. It
needs a Mac-host pass to be seen for real.

Test-harness gotchas for anyone touching these: `PinPopover`'s `anchor` prop is a real
`HTMLElement` (it calls `getBoundingClientRect`), not a rect literal; and a launcher tile's
accessible name is its **content** (the app name), not its `title` attribute.

---

# NIC-177 — Keychain permission repeatedly

**No increment. Already built and committed.** Status "Testing" is accurate.

Verified present on `dev`: `SecretValueCache` (`KeychainSecretCapability.swift:221`), rotation-only
token persist (`SpotifyAuthSession.swift:139`), and the `onSecretDeleted` hook
(`BridgeSession.swift:1555`).

**Remaining work is Nick's manual pass** on a fresh rebuild: prompts should be at most one per
secret per launch and should not recur hourly.

If they still recur, the residual cause is the ad-hoc signature — every rebuild orphans every
"Always Allow" because macOS pins keychain ACL grants to the binary's `cdhash` when there is no
designated requirement. Two unbuilt options, both previously presented and held:

1. **Apple Developer Program → Developer ID / Team ID.** The real fix: stable designated
   requirement + `teamid:` partition, and it unblocks `kSecUseDataProtectionKeychain` (no ACLs, no
   prompts ever). A purchase decision.
2. **Explicit allow-all ACL** via `SecAccessCreate` + `SecACLSetContents(acl, nil, …)`. Works today,
   no account. **Security downgrade** — any local process could then silently read the
   GitHub/Linear/Google/Spotify tokens.

A self-signed cert does **not** help: with no Team ID the partition list still falls back to
`cdhash:` and still breaks on rebuild. (Verified empirically 2026-08-04.)

---

# NIC-115 — Migrate SQLite engine to GRDB

**Probed 2026-08-05 in a throwaway package: GRDB 7.11.1 builds and runs on Swift 6.3.3 / macOS 26.**
`DatabaseQueue`, raw SQL, and `DatabaseMigrator` (incl. `appliedIdentifiers`) all verified working.
Do not re-probe.

### Two facts that shape the plan

1. **Linux CI needs a package.** GRDB's `Package.swift` declares its SQLite as
   `.systemLibrary(providers: [.apt(["libsqlite3-dev"])])`. The `core-swift-linux` job runs the bare
   `swift:6.1` image (`.github/workflows/ci.yml:114`), which does not ship it. **This is the Windows
   problem relocated** — plan it, don't discover it. There is no Windows CI; the targets are Linux
   and macOS only.
2. **The seam is genuinely clean.** Only `SQLiteDatabase.swift` imports the engine, behind a
   six-method surface (`execute`, `run`, `query`, `transaction`, `lastInsertRowID`,
   `init(location:create:busyTimeoutMs:)`) plus `SQLiteRow` / `SQLiteValue`. All 20 store files ride
   that API.

**Owner decision — acceptance trimmed:** strike the "FTS5 search path adopted via GRDB" criterion.
**No FTS5 exists anywhere in the tree**, so there is nothing to adopt.

### ⚠️ BLOCKER FOUND 2026-08-05 — increments 1–3 below are NOT separable

**GRDB and `swift-toolchain-sqlite` cannot coexist in any target that compiles GRDB.** Proven by
building it, not by reading docs. The tree was reverted; nothing landed.

**Mechanism (exact):** `swift-toolchain-sqlite`'s module map exposes **both** headers in one module:

```
module SwiftToolchainCSQLite {
  header "sqlite3.h"
  header "sqlite3ext.h"
}
```

`sqlite3ext.h` is SQLite's *loadable-extension* header: when `SQLITE_CORE` is undefined it redefines
every SQLite API as a macro routing through a global `sqlite3_api` pointer. GRDB's C shim does
`#include <sqlite3.h>`, clang resolves that into the vendored module, drags in `sqlite3ext.h`, and
every call in the shim becomes a macro referencing an undeclared symbol:

```
GRDBSQLite/shim.h:15:5: error: use of undeclared identifier 'sqlite3_api'
error: could not build Objective-C module 'GRDBSQLite'
```

**Scope of the conflict, measured:**

| Situation | Result |
|---|---|
| GRDB in the graph, nothing imports it | ✅ builds; suite green (1398) |
| GRDB linked into `CerebralStorage`, sources don't import it | ✅ builds; suite green |
| A target imports **both** GRDB and `CerebralStorage` | ❌ shim fails |
| A target imports **only** GRDB but links `CerebralStorage` | ❌ shim fails |

The last row is the killer: it is not about import statements, it is about the vendored module map
being visible anywhere GRDB's shim compiles. No include-path ordering fixes it.

**Consequence:** the "add it, then swap it, then remove the old one" sequence is impossible — the
moment `SQLiteDatabase.swift` imports GRDB while the target still links `SwiftToolchainCSQLite`, the
build breaks. **Old increments 1–3 must become one atomic commit.** Feasibility of the end state is
already established: GRDB 7.11.1 was probed standalone on Swift 6.3.3/macOS 26, and
`DatabaseQueue.unsafeReentrantWrite(_:)` exists, which is what maps this wrapper's re-entrant
`transaction(_:)` semantics (its body calls back into `run`/`query` on the same instance).

### Increment 1 (REVISED) — Atomic engine swap

- **Goal:** `CerebralStorage` runs on GRDB, with `swift-toolchain-sqlite` gone, in one commit.
- **Changes, all together because they cannot be split:** add GRDB and remove `swift-toolchain-sqlite`
  in `Package.swift`; rewrite `SQLiteDatabase`'s internals over `DatabaseQueue` preserving its public
  API **exactly** (`execute`/`run`/`query`/`transaction`/`lastInsertRowID`/`Location`/`busyTimeoutMs`,
  `@unchecked Sendable`); map GRDB errors onto the existing `StorageError` cases; use
  `unsafeReentrantWrite` so `transaction(_:)` keeps its re-entrant contract; add
  `apt-get install -y libsqlite3-dev` to the `core-swift-linux` job; supersede ADR-005.
- **Acceptance:** the entire existing `StorageTests` suite passes **unmodified**. That is the whole
  safety argument for a change this size — the tests are the spec.
- **Still deferred:** `DatabaseMigrator` (migration bookkeeping is durable user state), GRDB record
  types, value observation, FTS5.

The three sub-sections below are kept for their detail but are now one commit.

### Original increment 1 — Add GRDB and provision Linux CI *(folded into the atomic swap)*

- **Changes:** dependency in `Package.swift`; `apt-get update && apt-get install -y libsqlite3-dev`
  in the `core-swift-linux` job before `swift test`.
- **Files:** `Package.swift`, `Package.resolved`, `.github/workflows/ci.yml`.
- **Note:** a dependency nothing links is only *resolved*, never compiled — so this could never have
  proven GRDB builds on Linux even without the conflict above.

### Increment 2 — Reimplement `SQLiteDatabase` over GRDB

- **Goal:** the engine swaps with **zero** changes to the 20 callers.
- **Changes:** rewrite `SQLiteDatabase`'s internals over `DatabaseQueue`, preserving the public API
  **exactly** — including `busyTimeoutMs`, the `Location` enum, and `@unchecked Sendable` semantics.
  Map GRDB errors onto the existing `StorageError` cases.
- **Files:** `packages/storage/Sources/CerebralStorage/SQLiteDatabase.swift`, `StorageError.swift`,
  `Tests/StorageTests/`.
- **Owner decision — do NOT adopt `DatabaseMigrator`.** Keep the hand-rolled `SchemaMigration`
  framework and its checksums. The migration table is user-owned durable state; swapping its
  bookkeeping is a separate, riskier change with a real migration path, and nothing forces it now.
- **Tests:** **the entire existing `StorageTests` suite must pass unmodified — that is the
  acceptance criterion.** Plus explicit coverage of transaction rollback, busy-timeout behaviour
  under contention, and the empty/upgrade/checksum cases CI already exercises.
- **Done when:** `StorageTests` green on both platforms with no test file edited; a real
  `cerebral.db` opens and reads under the new engine.
- **Deferred:** `DatabaseMigrator`, GRDB record types, value observation, FTS5.

### Increment 3 — Drop `swift-toolchain-sqlite`

- **Changes:** remove the dependency and the `SwiftToolchainCSQLite` product from the storage target.
- **Done when:** clean build from a wiped `.build` on both platforms.
- **Depends on:** Increment 2 green and committed. Separate so a rollback is one revert.

---

# NIC-123 — 5th `ToolCapabilities` slot → SIGBUS

**The ticket's premise is stale.** It claims a **5th** existential slot triggers SIGBUS. On today's
tree `ToolCapabilities` carries **23 existential slots**
(`packages/tools/Sources/CerebralTools/Adapters/ToolCapabilities.swift:14-70`) and the suite runs
green at ~1370 tests. The struct grew 18 slots past the stated trigger without reproducing.

The toolchain has also moved: the crash was recorded on the July Xcode default; the machine is now
on **Swift 6.3.3**. An upstream codegen fix is the most likely explanation.

So the work is not "reproduce and fix" — it is **"run the experiment and close it."**

**Owner decision:** close with evidence, don't cancel. Cancelled implies "we decided not to"; this
was a real reproducible crash that appears to have been fixed underneath us, and it's worth an hour
to retire a High-priority unknown properly.

### ✅ RESOLVED 2026-08-05 — the crash does not reproduce, and the slot should stay off anyway

**Experiment run, per the original bisection protocol.** The `secret: any SecretCapability` slot was
re-added to `ToolCapabilities` in the exact shape recorded as SIGBUS-ing 5/5 on 2026-07-05 (default
argument form, plus the honest `KeychainSecretCapability` bound at the Mac composition), then:

| Run | Result |
|---|---|
| `swift test` ×10 with the slot present | **10/10 green**, 1398 tests each |
| `CEREBRAL_KEYCHAIN_TESTS=1 swift test --filter MacAdapterTests` ×3 | 2 pass, 1 fail — **unrelated**, see below |

**Evidence:** Apple Swift 6.3.3 (swiftlang-6.3.3.1.3), arm64-apple-macosx26.0, macOS 26.5.2. The
struct now carries 23 existential members — 18 past the "5th slot" the ticket blames — so the
premise was already disproven by the tree before the experiment ran. Most likely a toolchain codegen
bug fixed upstream between the July Xcode default and 6.3.3.

**The slot was reverted, and should NOT be re-added.** The ticket's last to-do says the struct "may
regain the `secret` slot if that shape is preferable" — it is not. Grepping the handlers found
**zero** consumers: no tool handler references `SecretCapability` at all, and every real consumer
(`SpotifyAuthSession`, `GoogleAuthSession`, `ReleasesPublisher`, `ProjectGitStatusPublisher`,
`LinearAPIClient`) takes `secretStore` straight off `MacToolCapabilities.Composition`. NIC-82's
placement is correct on its own merits — the comment there already says so ("carried here rather
than on `ToolCapabilities` because no tool handler consumes secrets in the MVP"). Re-adding it would
mean a dead field on the one struct this ticket suspected of memory-corruption sensitivity.

**Bearing on NIC-115:** the vendored `swift-toolchain-sqlite` is **exonerated** — it was the prime
suspect in every recorded crash trace, and the crash is gone with it still in place. That removes the
diagnostic argument for the GRDB migration, leaving only "FTS5 someday".

**Separate pre-existing bug found and fixed while running the protocol.** The 1-in-5 keychain
failure was not a SIGBUS but a clean `.notFound` assertion, and it reproduced identically with the
slot **reverted** — so it is not the experiment's doing. Cause: `storeIsWriteThrough` seeded
`SecretValueCache.shared` and then asserted a value survived a Keychain delete, while the
round-trip test above it calls `SecretValueCache.shared.invalidateAll()` to prove persistence.
swift-testing runs those in parallel, so the invalidation could land between the store and the read.
NIC-177's process-wide cache made these two tests race by construction. Fixed by giving
`storeIsWriteThrough` a private `SecretValueCache()` — the property under test is the cache's
behaviour, not that one shared instance, which `SecretValueCacheTests` covers separately.
**8/8 green after the fix, from ~1-in-5 failing before.**

### Original increment 1 — Re-run the original experiment *(done; see above)*

- **Goal:** an evidence-backed answer on whether the crash still exists.
- **Changes:** add the `secret: any SecretCapability` slot exactly as NIC-82 did — the shape recorded
  as SIGBUS-ing 5/5 — and run the full suite **10×**.
  - **If green:** migrate the Keychain adapter off the `MacToolCapabilities.Composition.secretStore`
    workaround onto the slot (the ticket's own final to-do), record the toolchain versions as
    closing evidence, close the ticket.
  - **If it crashes:** stop, **do not commit**, hand the tree to Increment 2.
- **Files:** `ToolCapabilities.swift`, `apps/mac/Sources/CerebralMacAdapters/MacToolCapabilities.swift`,
  the mock factory, composition sites.
- **Tests:** `swift test` ×10 plus `CEREBRAL_KEYCHAIN_TESTS=1 swift test --filter MacAdapterTests` ×3
  — matching the original bisection protocol so results are comparable.

### Increment 2 — ASan, only if Increment 1 still crashes

- **Changes:** `swift test --sanitize=address` on the crashing shape. If ASan fingers
  `swift-toolchain-sqlite`, audit its `SQLITE_THREADSAFE` configuration against our concurrent test
  usage. If it fingers nothing, build a minimal repro in a fresh package and file it upstream.
- **Note:** if NIC-115 landed first, `swift-toolchain-sqlite` — the busiest suspect in every recorded
  crash thread list — is **gone from the graph entirely**, which may resolve this by itself. That is
  why NIC-115 is sequenced first.

### Original bisection evidence (2026-07-05, for comparison)

| Tree state | Result |
|---|---|
| HEAD (d382bbb) | green 4× |
| HEAD + 3 meaningless padding structs, same file | green 6× |
| HEAD + `secret` slot with default arg | SIGBUS ~every run |
| HEAD + `secret` slot, explicit args everywhere | SIGBUS 5/5 |
| HEAD + slot, keychain code and tests entirely absent | SIGBUS |
| Slot removed, adapter on `Composition` instead | green 12× |

Crash was `SIGBUS / EXC_BAD_ACCESS KERN_PROTECTION_FAILURE` at a **constant dyld-shared-cache
address** (`_swiftEmptySetSingleton`, a read-only page), from random unrelated tests.

---

# NIC-116 — Migrate frontmatter parsing to Yams

**Probed 2026-08-05 with Yams 5.4.0 on Swift 6.3.3. It builds and runs — but a byte-stable
round-trip is NOT achievable by configuration.** Do not re-probe; do not try to tune your way out
of this.

| Input | Yams round-trip | Cause |
|---|---|---|
| `created: 2026-08-05` | `created: 2026-08-05T00:00:00Z` | implicit timestamp resolution → `Date` |
| same, with `Resolver.default.removing(.timestamp)` | `created: '2026-08-05'` | stays a `String`, but gets **quoted** to prevent re-resolution |
| `id: 007` | `id: 7` | YAML 1.1 int coercion |
| `tags:` / `  - a` | `tags:` / `- a` | libyaml never indents block sequences under a mapping; the `indent:` option does **not** affect it |

A naive swap would **rewrite every note in the vault on first touch**, failing NIC-116's own
acceptance criterion ("no reformatting of durable note files").

### The resolution is better than a workaround

`FrontmatterCodec.emit` is called in **exactly one place** — `MarkdownKnowledgeService.swift:54`, on
note *capture*. `parse` is called in three read paths (`:93`, `:156`, `:249`). **CerebralHelm never
rewrites an existing note's frontmatter.** The codec is already asymmetric, so Yams belongs on the
read side only.

That is also where the real bug is. The current parser is a line-splitter requiring a colon per
line (`FrontmatterCodec.swift:48`), so an Obsidian note with

```yaml
tags:
  - work
  - urgent
```

parses `tags` to `""` and **silently drops both tags**. Multiline scalars, nested maps, and quoted
colons are mangled the same way.

**Owner decision:** proceed with read-path-only. The ticket's acceptance text asks for a parse
*and emit* swap and **needs rewording in Linear** to match.

### Increment 1 — Yams on the frontmatter read path

- **Goal:** Obsidian-authored notes (lists, nested maps, multiline scalars, quoting) parse
  correctly; written notes are untouched.
- **Changes:** add Yams to `Package.swift`; reimplement `FrontmatterCodec.parse` over `Yams.load`
  with `Resolver.default.removing(.timestamp)` (so ISO dates stay strings, matching what `emit`
  writes); add a **deterministic `Any → String` flattening** at the boundary so the existing
  `[String: String]` return type is preserved — scalars verbatim, sequences joined, nested maps
  flattened or dropped by an explicit documented rule. **Leave `emit` entirely unchanged.**
- **Files:** `Package.swift`, `packages/knowledge/Sources/CerebralKnowledge/FrontmatterCodec.swift`,
  `Tests/KnowledgeTests/`.
- **Contracts:** no schema change, no migration. Vault files are read-only on this path.
- **Tests:** the tag-list case that's broken today; multiline scalars; quoted colons; a malformed
  block degrading to the current "empty map, whole content as body" behaviour; and a **round-trip
  guard** asserting `parse(emit(x))` is stable so the two halves can't drift.
- **Done when:** an Obsidian note with a tag list round-trips its tags, and no note file is modified
  by any read.
- **Deferred — explicitly rejected:** Yams on the emit side. That is the vault-churn path.

**BUILT 2026-08-05.** Gates: `swift test` **1411** green · **xcodebuild BUILD SUCCEEDED** ·
repository-boundary tests green. Yams 5.4.0. No dashboard change.

**Design change from the plan — `compose`, not `load` + resolver surgery.** The plan said to use
`Yams.load` with `Resolver.default.removing(.timestamp)`. That only patches one coercion; `load`
applies YAML's *implicit resolution* to every scalar, so `007` still became the integer `7`, `no`
became `false`, and `1.50` became `1.5`. All of those lose the author's literal text on the way into
a `[String: String]` map. `Yams.compose` returns the node tree, where `Node.Scalar.string` is the
**verbatim source text** — one change that sidesteps the entire family of resolver quirks instead of
disabling them one at a time. Pinned by a test.

**What the old parser was actually doing** (measured by running the new tests against it, not
inferred):

| Input | Old result | Now |
|---|---|---|
| `tags:` / `  - work` / `  - urgent` | `""` — both values dropped | `"work, urgent"` |
| `tags: [work, urgent]` | `"[work, urgent]"` raw | `"work, urgent"` |
| `summary: \|` + indented lines | **`"\|"`** — the block indicator became the value | the block's text |
| `author:` / `  name: Nick` | key absent | `author.name` |
| `title: "Meeting: Q3 planning"` | `"Meeting"` — split on the first colon | full string |
| malformed YAML | **`["title": "[unclosed", "bad": ": :"]`** — fabricated keys | `[:]`, body kept |

That malformed-YAML row is the worst of them: the old parser invented metadata out of unparseable
text rather than declining to read it.

**Flattening rules** (a flat `[String: String]` has to project richer YAML somehow — documented on
`flatten`): scalar → literal text; sequence → joined `", "`; mapping → recursive dotted keys
(`author.name`); null → `""` (matching the old behaviour); **alias (`*anchor`) → omitted**, because
resolving it wrongly would put text in a note's metadata that the author never wrote.

`unquote` was deleted — Yams owns quoting and escapes now.

**Two halves kept honest by a round-trip guard**: the codec is deliberately asymmetric, so a test
asserts everything `emit` writes is read back identically, using a title containing quotes, a
backslash and a colon. A second test covers the realistic lifecycle — CerebralHelm captures a note,
the user adds a tag list in Obsidian, both halves still read.

### Increment 2 — Reconcile the duplicate reader

`packages/shared/Sources/CerebralShared/MarkdownFrontmatter.swift` is a second frontmatter reader,
existing solely because `CerebralCore` cannot import `CerebralKnowledge` (siblings, per the
repository boundary rule).

- **Changes:** either move the Yams-backed parse into `CerebralShared` and have `CerebralKnowledge`
  delegate, or keep them separate and add a shared conformance test proving identical behaviour.
  Decide during the increment; the boundary rule constrains the answer.
- **Tests:** the same fixture set against both entry points.
- **Depends on:** Increment 1.

**BUILT 2026-08-05 — NIC-116 feature-complete.** Gates: `swift test` **1414** green ·
**xcodebuild BUILD SUCCEEDED**.

**Decision: keep both readers. Do NOT move Yams into `CerebralShared`.** The plan offered that as
one of two options; the evidence says it is wrong. *Every* package depends on Shared, so putting a
C-backed YAML parser there pulls libYAML into Core, Tools, Storage and Contracts — to serve **one
integer key**. `MarkdownFrontmatter` is read by exactly two files, for exactly `importance`, from a
`PROJECT.md` whose frontmatter is `importance: <int>` in both `ProjectScaffolder.descriptorContents`
and the shipped `config/templates/PROJECT.md`. The narrow parser matches its job precisely; the
duplication is justified rather than accidental.

**The decision is now enforced, not just documented.** Added a `RepositoryBoundaryTests` case —
*"only CerebralKnowledge imports the YAML parser"* — mirroring the existing SQLite-engine
confinement, including its non-vacuous guard (it fails loudly if the import disappears rather than
passing on an empty scan). A future attempt to import Yams elsewhere now fails a test instead of
silently widening the graph.

**Drift is guarded by a conformance test.** `FrontmatterParserConformanceTests` runs *both* readers
over the flat-scalar grammar they share — single/multiple scalars, quoted values, empty values, no
block, unterminated block, empty document, a body containing a `---` rule, multi-paragraph bodies —
plus the exact bytes the scaffolder writes. They agree on all of it. Cases where they legitimately
differ (sequences, nested mappings, block scalars, malformed YAML) are deliberately **not** asserted
there — those belong to `FrontmatterCodec` alone.

Both types now carry doc comments explaining the split, pointing at each other and at the tests, so
the next reader finds a decision rather than an apparent oversight.

---

## Linear edits owed

Not done during planning (read-only session). Someone should apply these:

- **NIC-115** — strike the FTS5 acceptance criterion; note that `DatabaseMigrator` is deliberately
  not adopted.
- **NIC-116** — reword acceptance to read-path-only; record why emit-side Yams was rejected.
- **NIC-123** — note that the "5th slot" premise is stale (23 slots today, suite green) and that the
  plan is now an experiment, not an investigation.
- **NIC-175** — record that the Steam symptom was the file copy, not a defect, and that the ticket
  proceeds for nested-folder discovery and the missing install event.
