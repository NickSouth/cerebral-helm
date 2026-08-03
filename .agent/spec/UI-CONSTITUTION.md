# CerebralHelm UI Constitution

**Status:** Working constitution for the PRE-UI dashboard (NIC-50 epic).
**Owner of this artifact:** NIC-51 (PRE-UI-1). Later increments **consume** it.
**Derived from:** [`CEREBRALHELM_DESIGN_SPEC.md`](CEREBRALHELM_DESIGN_SPEC.md) +
[`../../wiki/CerebralHelm-Visual-Design-Reference.pdf`](../../wiki/CerebralHelm-Visual-Design-Reference.pdf).

## 0. What this document is (and is not)

This is the **text constitution** every UI increment reads at the start of its work.
The visual reference is a PDF — an image the model would otherwise have to
re-interpret every time. This file distills its salient, binding decisions into text
so they are read, not re-guessed.

**Precedence (highest wins):**

1. The user's latest explicit instruction.
2. [`CEREBRALHELM_DESIGN_SPEC.md`](CEREBRALHELM_DESIGN_SPEC.md) — the UI authority.
3. **This constitution** — the working distillation.
4. The visual PDF — mood, density, composition.

If this file and the design spec diverge, **the design spec wins** — fix this file.
This file never invents scope; it records what the spec + PDF already decided.

> **Token values below are PROPOSED and owner-tunable.** They are committed so work
> can proceed (per the NIC-117 "live-tunable semantic tokens" direction), then tuned
> in place. Tuning a value is **not** a contract change — it never requires touching a
> component, only the token source.

## 1. The one rule that prevents drift

**Consume; never re-derive.** Every increment reads tokens, contracts, and
conventions from the foundation (this file + the token source + the bridge
contracts). No increment re-reads the PDF to pick a color, re-invents a spacing
value, or branches on mode inside a component. A value that isn't in the token
source yet is **added to the token source and to this file**, never inlined.

## 2. Per-increment consistency checklist

Every UI increment — foundation or feature — must satisfy all six before it is "done":

1. **Reuses existing tokens/components.** No new raw hex, px, or duration literals in
   components. A genuinely missing value is added to the token source **and** recorded
   here, then referenced — never inlined.
2. **Adds no one-off colors.** All color flows through semantic tokens. Mode color is
   applied **only** via the `data-mode` mechanism (§5), never a per-mode conditional in
   a component.
3. **Conforms to the shell grammar (§6).** Region placement, the panel primitive, the
   4+4 quick-action geometry, neutral-blue confirmation, and bottom-bar-accent-on-home-
   only are honored.
4. **Adds visual-regression coverage.** Every new visual fixture/state gets a snapshot
   at the three viewport classes (§8); anything animated also gets a reduced-motion
   snapshot.
5. **Honest-unavailable for anything not wired.** No action, widget, or capability is
   shown as successful when the bridge can't perform it. Unwired surfaces render as
   visibly disabled/unavailable (FR-UI-07; see NIC-58, NIC-64).
6. **Consumes this constitution.** Tokens/contracts/conventions come from the
   foundation; the PDF is not re-interpreted.

## 3. Token model

One source of truth, implemented in NIC-51 Increment 2 under
`apps/dashboard/src/tokens/` (a CSS custom-property layer + a typed map + a generated
manifest the resolution gate reads). Naming convention: CSS variables are prefixed
`--ch-`. Config files reference **semantic token names** (dotted), e.g.
`config/modes/executive.json → theme.accentPrimary = "executive.primary"`. The gate
(Increment 4) fails the build if a config token name resolves to no registered token.

| Layer | Examples | Rule |
|---|---|---|
| **Primitives** | raw palette, spacing scale, radii, durations | Never referenced by components directly. |
| **Semantic** | `--ch-accent-primary`, `--ch-panel-border`, `--ch-status-success`, `--ch-focus-ring` | The only tokens components may use. |
| **Mode palettes** | `--ch-mode-executive-primary` … resolved into `--ch-accent-*` under `[data-mode]` | Switched by `data-mode`, never by component logic. |

Design-spec semantic roles that must exist: `accent-primary`, `accent-secondary`,
`panel-border`, `glow-soft`, `status-success`, `focus-ring` (spec §6), plus the full
set below.

## 4. Color (proposed, owner-tunable)

### 4.1 Base surfaces (mode-independent)

| Token | Value | Use |
|---|---|---|
| `--ch-bg-base` | `#05080F` | App background base (deep navy-black) |
| `--ch-bg-gradient-top` | `#0A1422` | Top of the vertical background gradient |
| `--ch-glow-radial` | `rgba(95, 210, 232, 0.14)` | Top radial glow behind Heimlich |
| `--ch-surface-panel` | `rgba(15, 23, 38, 0.66)` | Translucent panel fill |
| `--ch-surface-raised` | `rgba(18, 26, 42, 0.92)` | Overlays (confirmation, settings, agent, app menu) |
| `--ch-panel-border` | `rgba(255, 255, 255, 0.08)` | Thin 1px panel outline |
| `--ch-text-primary` | `#EAF2FB` | Primary text |
| `--ch-text-muted` | `#9FB0C3` | Secondary text |
| `--ch-text-faint` | `#6B7C90` | Eyebrow labels, captions |

### 4.2 Mode palettes

PDF character per mode (spec §6): Executive = gold + cyan balance · Developer = cool
white/cyan, restrained (no neon) · School = electric blue + warm gold counter-accent ·
Entertainment = emerald/green + cool cyan.

| Mode | `…-primary` | `…-secondary` | Notes |
|---|---|---|---|
| `executive` | `#E8B765` (gold) | `#5FD2E8` (cyan) | Calm, premium; dominant gold |
| `developer` | `#7FC4DC` (restrained cyan) | `#AFC6D6` (cool white) | Restrained — avoid neon/saturation |
| `school` | `#3E7BFA` (electric blue) | `#E8B765` (warm gold) | Blue dominant, gold counter-accent |
| `entertainment` | `#34D38A` (emerald) | `#5FD2E8` (cyan) | Leisure feel; **identical density** to other modes (owner course-correction D.2 — palette differs, density is constant) |

`--ch-glow-soft` per mode is a low-alpha blend of that mode's primary→secondary, used
for the Heimlich field and panel glows. The ambient field recolors from these tokens
and **never embeds mode hex** (spec §5.8).

### 4.3 Status (mode-independent, never color-alone)

| Token | Value | Meaning |
|---|---|---|
| `--ch-status-success` | `#34D399` | Success / online / passing |
| `--ch-status-warning` | `#E8B765` | Review / warning / attention |
| `--ch-status-info` | `#5B8DEF` | Info / planning / in-progress |
| `--ch-status-error` | `#F2655E` | Error / failed |
| `--ch-status-neutral` | `#7C8BA0` | Idle / disabled / unavailable |

Status is **always** paired with text and a non-color cue (icon, shape, label). Per
the agent model (spec §5.10) the dashboard agent statuses are exactly **Idle /
Waiting / Thinking / Ready** — `Online` from the mockups is illustrative only.

### 4.4 Confirmation (mode-independent neutral system blue)

| Token | Value | Use |
|---|---|---|
| `--ch-confirm-accent` | `#4D8DF6` | Confirmation primary/affirmative accent |
| `--ch-confirm-surface` | `rgba(16, 24, 40, 0.96)` | Confirmation window fill — **no mode tint** |

The confirmation surface is **neutral blue regardless of active mode** (spec §9,
PLATE 05), even over the gold Executive dashboard. It never inherits `data-mode`
accent. The bottom bar takes the mode accent **on the home dashboard only** (spec
§5.12); the confirmation surface never does.

## 5. Mode application (the no-conditionals mechanism)

Mode is applied by setting `data-mode="executive|developer|school|entertainment"` on
a single root element (the `ThemeProvider`/app root, NIC-51 Increment 5, fed by
bootstrap-state mode). CSS resolves the active mode palette into the `--ch-accent-*`
semantic tokens:

```css
[data-mode="executive"] {
  --ch-accent-primary: var(--ch-mode-executive-primary);
  --ch-accent-secondary: var(--ch-mode-executive-secondary);
}
```

Components reference only `--ch-accent-primary` / `--ch-accent-secondary` / status /
surface tokens. **No component reads `mode` to choose a color.** This is the structural
guarantee behind NIC-51 AC-1 ("no scattered mode-color conditionals"). Switching mode
re-themes without remounting the shell (FR-UI-01).

## 6. Shell grammar (binding summary; full detail in the design spec)

Three-column desktop canvas + a persistent bottom bar on its own layout track:

- **Left rail (dense):** Today/Tonight · System Health · Free Widget A · News (3 links).
- **Center (calm, dominant):** Global Search · Quick Apps · Heimlich (ambient field +
  conversation overlay + the **4 compact bars over 4 boxes** quick-action geometry).
- **Right rail (operational):** Mode Switcher (4 fixed) · Agents (4 fixed) · Free Widget B.
- **Bottom bar (thin, persistent):** Heimlich state · weather · mode · Wi-Fi · battery ·
  date/time · settings. Takes mode accent **on home only**.

Rules: panels are thin-outlined, translucent, **small radius**, **no nested card
stacks**; edges dense, center spacious; Heimlich is the largest and calmest surface;
text wraps before shrinking and critical values never clip; no region collapses into an
unexplained blank. Components express intent through `CerebralBridge` and never touch
the platform directly.

**Interaction invariants (owner course-correction — bound in the bootstrap contract):**

- **Heimlich always owns the center.** Every mode boots with the ambient field centered;
  nothing is "active" in the center by default. Chat is a translucent overlay over the
  still-running field (it **never** replaces it), with its own input **docked at the bottom**
  of the center. The top-center *Ask Heimlich* bar is a **separate persistent global
  launcher** (always visible, even mid-conversation) — two distinct input loci, not one
  search, and no floating command-palette modal. (`bootstrap.heimlich`.)
- **Agent workspaces cover the right column only.** Opening one of the four agents slides
  in a panel the **width of the right column** that covers the right column's contents and
  restores them on close. The center (Heimlich) and the **left column are unaffected** and
  never compress. Default: no agent expanded. (`bootstrap.expandedAgent`, default `null`.)
- **Mode switching is an animated theme transition** (cross-fade / motion), not an instant
  flip and not a loading/pending state; all four palettes preload (`bootstrap.modes`).
- **All modes share identical density** — palette/accent differs, density is constant
  (Entertainment is *not* lighter).
- **The 4+4 quick-action grid renders up to 8 slots.** A *configured* action that is not
  built yet is greyed, labeled, and disabled ("coming soon") — never hidden. An
  *unconfigured* (null) slot is omitted entirely; each slot keeps its quarter-row width so
  the remainder centers within its own row (`quickActions.registry.json` owns each action's
  label, icon, archetype, and dispatch target).
- **Agent status is runtime** (Idle / Waiting / Thinking / Ready, from events;
  `bootstrap.agents[].activity`), text + non-color cue; the config `status` stays the
  availability flag (`…availability`). Identity icons are fixed per agent id.

The shell itself is **NIC-53**; NIC-51 only ships the tokens, the container, and a
token-reference page — not the regions.

## 7. Spacing, radii, typography

**Spacing** (4px base): `--ch-space-1:4px` `-2:8` `-3:12` `-4:16` `-5:20` `-6:24`
`-8:32` `-10:40` `-12:48` `-16:64`.

**Radii:** `--ch-radius-sm:8px` `--ch-radius-md:10px` `--ch-radius-lg:12px`
`--ch-radius-pill:999px`. (The earlier scaffold's 20px is **out** — the spec mandates
small corner radii.)

**Typography:** system sans (SF Pro on the Mac target; Segoe UI fallback on the Windows
dev box).

| Token | Size / weight | Use |
|---|---|---|
| `--ch-font-display` | 2.25rem / 300 | Time, greeting (large + light) |
| `--ch-font-xl` | 1.75rem / 400 | Major headings |
| `--ch-font-lg` | 1.3rem / 500 | Panel values |
| `--ch-font-base` | 0.95rem / 400 | Body |
| `--ch-font-sm` | 0.85rem / 400 | Secondary |
| `--ch-font-label` | 0.72rem / 500, `letter-spacing:0.12em`, uppercase | Eyebrow labels (TODAY, SYSTEM HEALTH) |

## 8. Motion, focus, responsive, layering

**Motion:** `--ch-motion-fast:120ms` `--ch-motion-base:200ms` `--ch-motion-slow:320ms`;
standard easing `cubic-bezier(0.2, 0, 0, 1)`. Under `prefers-reduced-motion`, the
`--ch-motion-*` tokens collapse toward `0ms`, the Heimlich field pauses/greatly
simplifies, and **state is carried by text + color, never motion alone** (spec §5.8,
§14). The ambient field holds a 30fps floor and stays negligible under heavy local
compute; it pauses entirely when offscreen/backgrounded.

**Focus (keyboard):** `--ch-focus-ring-color:#7FB7FF` `--ch-focus-ring-width:2px`
`--ch-focus-ring-offset:2px`. Focus is shown via `:focus-visible` with a visible ring
**plus** offset (thickness, not color alone). All actions are keyboard reachable;
modals/search/agent/sidebar trap and restore focus; Escape dismisses the topmost
dismissible surface without closing CerebralHelm. Reduced-motion and focus tokens
existing is NIC-51 AC-3.

**Responsive viewport classes** (targets: 16″ MacBook logical, compact laptop,
1440p/4K external — values tunable):

| Class | Width | Behavior |
|---|---|---|
| `compact` | `< 1440px` | Collapse side rails to drawers/tabs; preserve Search, Heimlich, mode, bottom bar; no horizontal page scroll. |
| `laptop` | `1440–1919px` | Full three-column canvas. |
| `external` | `≥ 1920px` | Widen center + rails; cap line length / control width. |

"Laptop and external-display constraints are stable" is NIC-51 AC-2.

**Z-index:** `--ch-z-base:0` `--ch-z-raised:10` `--ch-z-bottombar:100`
`--ch-z-scrim:900` `--ch-z-overlay:1000` `--ch-z-tooltip:1100`.

## 9. Where downstream tickets bind

- **NIC-52** — bridge/store: fills the state-boundary seam; expands
  `DashboardBootstrapState` (NIC-117 d/e). Consumes tokens for nothing visual yet.
- **NIC-53** — the three-zone shell + region placement (§6).
- **NIC-54 / 58–64** — mode views, panels, widgets, command palette/quick actions,
  Heimlich field, agents, confirmation surface, settings, degraded states.
- **NIC-65** — comprehensive cross-browser visual-regression matrix (NIC-51 stands up
  the harness skeleton as the guardrail).
- **NIC-118** — identity assets (logo, agent/mode icons); placeholders until then.

Each opens by reading this file, then passes the §2 checklist.
