# PRE-UI Frontend — Plan (the roadmap)

The rest of NIC-50, ordered foundation-first. Each increment is commit-sized, leaves the repo green, and **consumes the constitution** (`.agent/spec/UI-CONSTITUTION.md`) rather than re-deriving tokens/contracts/conventions. See [STATUS.md](STATUS.md) for what's built; [HANDOFF.md](HANDOFF.md) for how to execute.

**Done:** Phases A–C, plus D1, D2, D3. **Next: D4.**

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
- **D4** (NIC-117 b / ex-NIC-113) — **NEXT.** Wire the trivial quick actions (e.g. `capture-note` → `bridge.captureNote`); add the **quickActions→workflow resolution gate** to `validate-config.mjs`. Unwired actions stay greyed/disabled. See [HANDOFF.md](HANDOFF.md) § D4.
- **D5** (NIC-62) — universal confirmation surface: neutral-blue review window, full disclosure, approve-not-default-focus, keyboard flow, expiry/invalidation; submits via `decideConfirmation`.
- **D6** (NIC-59) — persistent bottom bar: Heimlich state, mode (accent on home only), context, CPU/mem/network/time, settings, emergency; distinct loading/stale/unavailable/disconnected metric states; weather + battery honest-unavailable pre-Mac.

## Phase E — richer surfaces

- **E1** (NIC-60) — Heimlich state presentation: the generative **WebGL ribbon/spark field** (OGL) behind a `{ state, palette, audioLevel }` interface; presets + interpolation; ≥30fps with offscreen pause; reduced-motion clamp; **polish the conversation overlay/scrim** D3 stubbed (and optionally migrate the conversation to bridge-driven state).
- **E2** (NIC-61) — four expandable agent workspaces as a **right-column-width overlay** (covers the right column only); runtime status; honest-disabled inputs; access boundaries from agent config; no add-agent control.
- **E3** (NIC-63) — floating settings window: all sections, implemented controls enabled, read-only contract inspection, unavailable future capabilities, edits via the same `updateSettings` validation path, shutdown action; doesn't replace the dashboard.
- **E4** (NIC-64) — degraded states everywhere: loading/empty/offline/unavailable/error/recovery from the canonical failure fixtures; no blank screens; read-only recovery exposes no mutating controls.

## Phase F — hardening + assets

- **F1** (NIC-65) — comprehensive cross-browser visual-regression + a11y matrix (every canonical mode + state × Chromium/WebKit × 3 viewports). Note: cross-platform/CI baselines are the open gap (current baselines are win32-only).
- **F2** (NIC-118) — identity & asset kit: logo/wordmark, the four fixed agent icons (by id, mode-invariant), mode iconography, Heimlich per-mode tuning. Swap placeholders with no layout change. Do this **after** the shell + Heimlich field exist.

---

## Open follow-ups (not increments)

- **Linear:** reword the **NIC-54** acceptance criterion "Entertainment reduced work-widget density" → constant density (superseded by course-correction D.2; ADR-noted).
- **Tech-debt chip spawned:** add a `.gitattributes` (`* text=auto eol=lf`) to stop the CRLF-driven `check-contract-drift` false failures on Windows (see [HANDOFF.md](HANDOFF.md) § Gotchas).
- **Per-increment guardrail:** every visual increment re-baselines its Playwright snapshot and passes the constitution §2 checklist; per-mode visual coverage is deferred to **F1/NIC-65** by design.
