# PRE-UI Frontend — Plan (the roadmap)

---

## Phase A — data-contract foundation ✅

- **A1** (NIC-117) — widget/app registries + unified reference-resolution gate.
- **A2** (NIC-117 d) — expanded `DashboardBootstrapState` (eager modes/agents + active regions) + fixtures.
- **A3** (NIC-117 e) — `getRecentActivity` read-surface op (FR-OBS-04) on the bridge contract.

## Phase B — bridge + store ✅

- **B1** (NIC-52) — `CerebralBridge` interface + `MockCerebralBridge` (replays all lifecycle/failure fixtures).
- **B2** (NIC-52) — event-driven store behind the `DashboardStore` seam.

## Phase C — shell ✅

- **C1** (NIC-53) — three-zone shell + panel primitive + responsive collapse + bottom-bar track.

## Phase D — mode view + core surfaces

- **D1** (NIC-54) ✅ — config-driven mode view (apps/actions/widgets/schedule/news/health/greeting), one view for all four modes, no per-mode conditionals.
- **D2** (NIC-54 / 117h) ✅ — mode switcher wired to `applyMode` (animated cross-fade); Executive default (ADR-007).
- **D3** (NIC-58) ✅ (uncommitted) — two command loci (launcher + docked), capability-aware suggestions, conversation overlay; no floating modal.
- **D4** (NIC-117 b / ex-NIC-113) ✅ — wired the trivial `capture-note` quick action → `bridge.captureNote` (honest acknowledgement); added the **quickActions→workflow resolution gate** (`validateQuickActionWiring`) + wired-action manifest (loose: unknown ids = placeholders). Other actions stay greyed/disabled.
- **D5** (NIC-62) ✅ — universal confirmation surface: neutral system-blue review window, full disclosure, approve-not-default-focus, Escape-cancels, expiry/invalidation; submits via `decideConfirmation`. **Event-driven** (no bootstrap-state schema change) — disclosure arrives on `confirmation.changed`, folded into a runtime-only `activeConfirmation`.
- **D6** (NIC-59) ✅ — persistent bottom bar: Heimlich state, mode (accent on home only), CPU/mem/network/time, settings, emergency; distinct ready/stale/disconnected metric states; weather + battery honest-unavailable, Settings/Emergency honest-disabled. Live clock masked for visual determinism.

## Phase E — richer surfaces

- **E1** (NIC-60) —✅ Heimlich state presentation: the generative **WebGL ribbon/spark field** (OGL) behind a `{ state, palette, audioLevel }` interface; presets + interpolation; ≥30fps with offscreen pause; reduced-motion clamp; **polish the conversation overlay/scrim** D3 stubbed (and optionally migrate the conversation to bridge-driven state). See [HANDOFF.md](HANDOFF.md) § E1.
- **E2** (NIC-61) DELAYED — four expandable agent workspaces as a **right-column-width overlay** (covers the right column only); runtime status; honest-disabled inputs; access boundaries from agent config; no add-agent control.
- **E3** (NIC-63) — floating settings window: all sections, implemented controls enabled, read-only contract inspection, unavailable future capabilities, edits via the same `updateSettings` validation path, shutdown action; doesn't replace the dashboard.
- **E4** (NIC-64) ✅ — degraded states everywhere. A single posture seam (`useUiPosture` — `{ loading, offline, error, recovering, readOnly }`) derived from top-level `uiState` + a runtime-only `recovery` widening (folded from `system.status.changed`, D5 pattern). Top-level treatments: loading **skeleton**, offline/error/recovery **banner** with a specific non-mutating recovery action (full-width sibling of the canvas — never replaces the shell). **Read-only recovery suppresses every mutating control** (mode switch, quick actions, command submit, confirmation approve). Region matrix: new `EmptyState` + `StaleMarker` primitives, so `empty` (healthy zero-result) reads distinct from `unavailable` (disabled capability) and `stale` (amber) across News/Schedule/Widgets/Health. Canonical `system.dashboard.loading` + `failure.dashboard_error` fixtures added; `?state=offline|loading|error|recovery` previews each via HMR. Pure frontend — no contract/Swift change. **80 unit tests green** (+11), build green, node gates green.

## Phase F — hardening + assets

- **F1** (NIC-65) ✅— comprehensive cross-browser visual-regression + a11y matrix (every canonical mode + state × Chromium/WebKit × 3 viewports). Note: cross-platform/CI baselines are the open gap (current baselines are win32-only).
- **F2** (NIC-118) ✅— identity & asset kit: logo/wordmark, the four fixed agent icons (by id, mode-invariant), mode iconography, Heimlich per-mode tuning. Swap placeholders with no layout change. Do this **after** the shell + Heimlich field exist.

---

## Open follow-ups (not increments)

- **Visual suite is red on `dev` (pre-existing, not E4).** The animated WebGL Heimlich field is **unmasked/unfrozen** in `tests/visual/shell.spec.ts`, so all fullPage screenshots flake, plus one pre-existing axe violation. Confirmed by running Playwright on a clean HEAD (E4 stashed): identical 5 failures per browser. Fix belongs with NIC-60/E1 or F1/NIC-65: mask the `.heimlich__ribbon` canvas (like the clock) and/or freeze it to a deterministic first frame under the test/`prefers-reduced-motion` path, then re-baseline. E4 deliberately did **not** re-baseline (it would bake a random frame in and hide this).

- **Linear:** reword the **NIC-54** acceptance criterion "Entertainment reduced work-widget density" → constant density (superseded by course-correction D.2; ADR-noted).
- **Tech-debt chip spawned:** add a `.gitattributes` (`* text=auto eol=lf`) to stop the CRLF-driven `check-contract-drift` false failures on Windows (see [HANDOFF.md](HANDOFF.md) § Gotchas).
- **Per-increment guardrail:** every visual increment re-baselines its Playwright snapshot and passes the constitution §2 checklist; per-mode visual coverage is deferred to **F1/NIC-65** by design.
