# CerebralHelm Dashboard Design Specification

**Status:** Current design authority  
**Date:** 2026-06-24  
**Scope:** Desktop dashboard, mode variants, Heimlich interaction states, agent expansion, layout mode, fullscreen access, and persistent bottom bar

## 1. Purpose and authority

This document converts the current CerebralHelm mockups and product decisions into an implementation contract. It replaces older dashboard descriptions where they conflict with this specification. The mockups remain the visual reference for mood, density, composition, and interaction character; this document is authoritative for component placement, state behavior, naming, and mode-specific content.

Precedence for UI implementation:

1. Explicit decisions in this specification.
2. Current MVP PRD for product scope, safety, architecture, and release behavior.
3. Current mockups for visual grammar and intended feel.
4. Earlier Design Doc, Build Plan, and North Star for durable intent.

Mockup text, sample data, status labels, app choices, and exact spacing are illustrative unless this document makes them binding. Visual tuning may happen live without changing the component contract.

## 2. Product intent

CerebralHelm is the persistent command environment behind and around normal macOS applications. The dashboard is the usable home surface, not a marketing page or a conventional chat app. Heimlich is the assistant presence and interaction layer; CerebralHelm is the environment.

The dashboard should feel:

- futuristic, premium, calm, and operational;
- dense at the edges and spacious around Heimlich;
- dark and glassy without becoming a gamer HUD;
- visibly different by mode while remaining immediately familiar;
- alive through restrained motion, state, and light rather than decorative clutter.

## 3. Core implementation principle

All four modes use one shared dashboard composition. Modes supply configuration and data; they do not fork the page into four independent implementations.

The shared shell owns:

- responsive grid and region placement;
- panel primitives and interaction grammar;
- command search behavior;
- Heimlich idle and active-chat states;
- quick-app and quick-action rendering;
- agent status and expansion behavior;
- bottom-bar structure;
- loading, empty, stale, unavailable, disconnected, error, and reduced-motion states.

Mode configuration owns:

- semantic theme tokens;
- calendar filtering;
- quick apps;
- quick actions;
- left and right free widgets;
- news relevance profile;
- greeting and supporting copy;
- optional default layout action;
- active project, course, repository, or media context.

The React UI expresses intent and subscribes to state through `CerebralBridge`. Components must not directly launch apps, query the filesystem, call system APIs, contact model providers, or mutate knowledge.

## 4. Shared dashboard anatomy

The home dashboard is a three-column desktop canvas with a persistent bottom bar. The center column is dominant. The side columns are denser and should remain visually subordinate to Heimlich.

| Region | Position | Component | Binding content |
|---|---|---|---|
| L1 | Top left | Today / Tonight | Time, date, calendar link, and mode-relevant events |
| L2 | Middle left | System Health | CPU, memory, battery, and network speed |
| L3 | Lower left | Free Widget A | Mode-specific operational widget |
| L4 | Bottom left | News | Exactly three relevant linked headlines |
| C0 | Top center | Global Search | Spotlight-style search with `Ask Heimlich` first |
| C1 | Upper center | Quick Apps | One to five configured apps plus More Apps |
| C2 | Center | Heimlich | Ambient presence, greeting, quick actions, or active chat |
| R1 | Top right | Mode Switcher | Executive, Developer, School, Entertainment |
| R2 | Middle right | Agents | Four fixed agents with status and expansion |
| R3 | Lower right | Free Widget B | Mode-specific context list |
| B1 | Bottom | Persistent Bottom Bar | Heimlich, weather, mode, system status, date/time, settings |

### 4.1 Layout behavior

- The center column receives the largest flexible width.
- Side columns use stable minimum and maximum widths so operational rows remain readable.
- The bottom bar occupies its own layout track and never overlaps dashboard content.
- Panels use thin outlines, controlled translucency, and small corner radii. Avoid nested card stacks.
- Text wraps before shrinking. Critical values and action labels must never clip.
- The dashboard must remain usable when data is missing; no region may collapse into an unexplained blank.

## 5. Region specifications

### 5.1 Today / Tonight

The top-left panel contains:

- `Today` during the normal day or `Tonight` when the active context is evening-oriented;
- current local time;
- current date;
- a calendar icon or explicit schedule link;
- a concise list of relevant calendar items for the day;
- an action to open the full calendar or schedule.

Filtering rules:

| Mode | Calendar content |
|---|---|
| Executive | All calendar items, ordered chronologically |
| Developer | Development work, standups, reviews, engineering blocks, releases, and configured project events |
| School | Classes, labs, office hours, study blocks, academic deadlines, and configured campus events |
| Entertainment | Social plans, games, shows, concerts, leisure blocks, and other configured downtime events |

Filtering must be explainable and configurable. If an item is excluded from a tailored mode, it remains available in the full calendar. Empty state: show the time/date and a short `No relevant events` state without inventing events.

### 5.2 System Health

System Health has identical structure in every mode. Only semantic theme colors change.

Required metrics:

- CPU utilization percentage;
- memory utilization percentage;
- battery percentage and charging state;
- network upload and download speed.

Each metric supports `loading`, `live`, `stale`, `unavailable`, and `disconnected`. Color alone must not communicate health. Bars, values, labels, and state text remain readable in every theme.

### 5.3 Left free widget

| Mode | Widget | Purpose |
|---|---|---|
| Executive | Market Brief | Compact tracked stocks and market movement |
| Developer | Project Git Status | Current project build/test/branch/PR/deployment summary |
| School | Deadlines | Upcoming assignments and academic due dates |
| Entertainment | Spotify | Current or recent listening, playback, and queue entry point |

The widget is a named slot, not a hard-coded conditional inside the dashboard. Each widget defines its own data contract, empty state, action, and freshness indicator.

### 5.4 News

The bottom-left panel shows exactly three headline links. Headlines are selected by the active mode's relevance profile:

- Executive: broad important news, business, technology, finance, and personally significant events.
- Developer: software engineering, tools, dependencies, security, and active-project ecosystem news.
- School: campus, courses, academic topics, and education-related updates.
- Entertainment: games, music, film, television, sports, golf, fantasy, and configured interests.

Every item includes a headline and navigable destination. Source and freshness may appear when space allows. Loading, offline, and no-results states must preserve panel height to avoid layout shift.

### 5.5 Global search

The top-center search bar is a compact command and navigation surface modeled after Spotlight, with Heimlich as the default route.

Placeholder: `Ask Heimlich or type a command...`

Result order:

1. `Ask Heimlich` using the exact entered text.
2. Best matching installed application.
3. Relevant CerebralHelm destinations, settings, tools, files, projects, courses, repositories, media, or known commands.
4. Additional ranked local results.

`Ask Heimlich` is always first, including when an app name is an exact match. Keyboard navigation, pointer navigation, Escape dismissal, and a visible selected state are required. Search results are capability-aware and must not display an action as available when the bridge cannot perform it.

Submitting `Ask Heimlich` opens the active Heimlich conversation in the center panel. Voice activation follows the same conversation state when visible dialogue is required.

### 5.6 Quick Apps

Quick Apps contains:

- zero to five user-configurable app shortcuts;
- a final `More Apps` control that opens a searchable menu of all discovered applications on the device.

Default emphasis:

| Mode | Suggested defaults |
|---|---|
| Executive | Chrome, Gmail, Finder, Claude Desktop, plus one configurable slot |
| Developer | VS Code, Terminal, GitHub, Docker, Linear |
| School | Canvas, Google Drive, Claude Desktop, Gmail, Quizlet |
| Entertainment | Spotify, YouTube, Steam, Discord, Photos |

These are shipped defaults, not permanent hard-coding. Missing or unavailable apps show an actionable unavailable state and remain editable.

### 5.7 Heimlich center

The center panel has a persistent `ambient` view — Heimlich's consciousness — and a `conversation` overlay composited above it.

#### Ambient view

Contains:

- Heimlich label and current system state;
- mode-aware system greeting;
- Heimlich's consciousness: the animated ribbon field (see 5.8);
- optional concise contextual summary;
- exactly eight quick actions at the bottom.

Quick-action geometry is binding:

- first row: four compact horizontal action bars;
- second row: four slightly larger action boxes;
- all actions remain inside the shared Heimlich component;
- actions are configurable by mode;
- Developer, School, and Entertainment each include `Open [Mode] Layout` as one of the eight actions.

Executive actions emphasize broad daily orchestration. The other modes emphasize their specific workflow and default layout.

#### Conversation overlay

Conversation does not replace the ambient view — it is a translucent overlay composited **above the still-running consciousness** (see PLATE 05). The animation never stops; on output it eases aside and lowers energy (the `success` motion signature in 5.8) so the chat reads clearly while the stream continues behind it.

The overlay opens after a typed Heimlich prompt, a voice request requiring visible dialogue, or an explicit open-chat action. It contains:

- a scrollable chat transcript of slightly transparent message bubbles, with activity trace where appropriate;
- tool, source, and status surfaces required for trust;
- a persistent text-and-send box at the bottom;
- a small minimize-chat control.

The overlay must carry enough contrast — a soft scrim or backdrop blur behind the bubbles — that text meets contrast requirements regardless of the animation behind it (NFR-08, FR-UI-09). Minimizing lifts the overlay and may preserve conversation history per product settings. With no overlay active, the consciousness returns to full ambient idle and the quick actions are unobscured.

Heimlich system states include `idle`, `listening`, `thinking`, `acting`, `awaiting_confirmation`, `success`, and `error`. State must be communicated through text and motion, not color alone.

### 5.8 Heimlich motion system

The ambient view is **Heimlich's consciousness**: a continuous, organic, futuristic, non-repeating field of ethereal ribbons that drift, break off, and throw sparks. It is generative, not a baked timeline — ribbon control points are advected through a slowly evolving seeded noise (flow) field, with short-lived spark particles emitted at high-energy points. Colors are drawn from the active mode's semantic tokens (`accent-primary`, `accent-secondary`, `glow-soft`); the field recolors per mode and never embeds mode-specific hex values.

It is one system driven by one parameter set (drift speed, turbulence, energy, color-shift rate, dispersion, center-bias, spark rate). Heimlich's states are **presets** of those parameters; transitions are smooth interpolations between presets, never separate animations or hard cuts.

State motion signatures:

| State | Signature |
|---|---|
| `idle` | slow ethereal drift, low energy, gentle color shift, centered |
| `thinking` | high energy with an amplitude pulse ("bounce"), increased sparks |
| `acting` | directed, flowing energy with moderate sparks; purposeful, not agitated |
| `awaiting_confirmation` | motion settles toward still; a slow color shift continues; minimal sparks. State is still carried by the persistent text label — never color alone, never motion alone |
| `success` | the field eases aside (center-bias shifts) and lowers energy to make room for the conversation overlay, then returns to idle when the overlay lifts |
| `error` | a brief, contained disturbance that settles, with a shift toward the status token; always accompanied by the text state |
| `offline` / disconnected | dimmed, desaturated, near-static |
| `listening` | audio-reactive; **deferred to the voice (North Star) phase** — no MVP motion signature |

Implementation direction:

- use a small WebGL renderer (a micro-library such as OGL or regl); the ribbon and spark density makes Canvas 2D insufficient for the target richness at the required frame budget;
- separate the slowly evolving field from short state-reactive pulses;
- use seeded noise with long, offset time domains so obvious loops do not emerge;
- the renderer is an isolated component taking `{ state, palette, audioLevel }`; `audioLevel` is a wired-but-unfed port until the voice phase;
- **never drop below 30fps**, and yield aggressively — reduce particle density and frame rate when the dashboard is unfocused, on battery, or thermally constrained — so that under heavy local compute (for example a 70B local model running) the renderer's own footprint stays negligible;
- pause the render loop entirely when the ambient surface is offscreen or backgrounded;
- pause or substantially simplify under reduced-motion, conveying state through the text label and color;
- keep text and controls in the DOM above the effect;
- never make animation required to understand status — the text label is always the primary status carrier.

Exact rendering parameters and the final frame budget are tuned after profiling on the target Mac; the 30fps floor and the negligible-footprint-under-load requirement are not negotiable.

### 5.9 Mode switcher

The top-right mode switcher always contains the same four controls in the same order:

1. Executive
2. Developer
3. School
4. Entertainment

The active mode has a strong selected state. Switching mode updates theme tokens and configured content while preserving the grid, focus logic, and component identity. Mode application may surface a pending state or action preview when it includes app, URL, hook, or layout actions.

### 5.10 Agents

The four initial agents are fixed:

- Research Analyst;
- Financial Advisor;
- Project Manager;
- System Janitor.

Agent identity icons never change by mode. Component surfaces and accents inherit the active mode theme.

Allowed compact statuses:

| Status | Meaning |
|---|---|
| Idle | No active or unread work |
| Waiting | Queued behind other work in sequential mode |
| Thinking | Currently running |
| Ready | Finished response exists and has not been opened |

The mockup label `Online` is illustrative and is replaced by this status model. Status must have text plus a non-color indicator. Selecting an agent expands the focused agent workspace with Chat, Context, History, linked knowledge, suggested next actions, status, and persistent input. The main canvas compresses or reflows; the panel must not cover critical controls.

### 5.11 Right free widget

| Mode | Widget | Purpose |
|---|---|---|
| Executive | Projects | Pinned or active projects and status |
| Developer | Repositories | Active repositories, branch, worktree, and concise state |
| School | Courses | Current courses and concise course state |
| Entertainment | Media List | Continue, queued, saved, or recently used media |

As with the left free widget, this is a registry-driven slot with a discrete data contract.

### 5.12 Persistent bottom bar

The bar is thin, stable, and always available. In normal dashboard mode it contains, left to right:

- Heimlich identity and state indicator;
- current weather;
- centered mode control;
- Wi-Fi state;
- battery state;
- date and time;
- settings access.

The bottom bar changes accent color with the active mode on the home dashboard only. System confirmation surfaces do not inherit mode color. In layout mode, bar items may be compacted or repositioned so the hot-swap control can occupy the central interaction position.

## 6. Mode contracts

| Concern | Executive | Developer | School | Entertainment |
|---|---|---|---|---|
| Role | General command center | Engineering workspace | Academic workspace | Downtime and media workspace |
| Visual character | Gold with cyan balance | Cool white/cyan, restrained | Electric blue with warm gold | Emerald/green with cool cyan |
| Calendar | All events | Engineering events | Academic events | Leisure/social events |
| Left free widget | Market Brief | Project Git Status | Deadlines | Spotify |
| Right free widget | Projects | Repositories | Courses | Media List |
| News | Broad priority | Engineering | Academic | Interest/media |
| Layout quick action | Optional general layout | Open Developer Layout | Open School Layout | Open Entertainment Layout |
| Greeting | Friendly Assistant | Development Copilot | Academic Partner | Downtime Concierge |

Mode color values are semantic tokens and remain tunable. Components reference roles such as `accent-primary`, `accent-secondary`, `panel-border`, `glow-soft`, `status-success`, and `focus-ring`; they do not embed mode-specific hex values.

## 7. Layout mode

Layout mode opens and arranges a configured working set of applications, windows, tabs, files, and project context. The School layout mockup is the interaction reference; Developer and Entertainment use the same system with different configuration.

Required behavior:

- the layout plan is generated from versioned configuration;
- unsupported or missing apps are shown before execution when relevant;
- high-risk actions are confirmed through policy, not by the layout component;
- the bottom bar exposes a hot-swap control for changing active project/course/context without rebuilding the whole layout;
- CerebralHelm remains reachable through the bottom bar and fullscreen sidebar;
- the user can return to the dashboard or close layout-managed windows through clear controls;
- partial success is visible and recoverable.

Layouts are context bundles, not saved screenshots. They may define application identities, URLs, tab groups, project paths, window roles, and approximate placement while allowing native adapters to resolve platform-specific geometry.

## 8. Fullscreen sidebar

When another application is fullscreen, a left-edge reveal provides a compact CerebralHelm surface without forcing the user out of the application.

The sidebar contains:

- Heimlich identity and state;
- global command/search entry;
- mode switching;
- compact quick actions;
- relevant schedule;
- quick apps;
- four agents;
- return-to-dashboard;
- collapse control.

The sidebar uses the same data and intent contracts as the dashboard components. It is a responsive composition, not a second implementation of the product.

## 9. Confirmation system

Confirmation is a universal policy-owned safety surface. It is neutral system blue regardless of active mode or layout.

For a gated action, show:

- the exact action;
- destination or recipient;
- affected app or service;
- content preview or command preview;
- consequences when relevant;
- Approve, Review, and Cancel actions;
- an explicit statement that nothing proceeds without approval.

The UI submits a decision to the bridge. It never decides risk classification, bypasses policy, or executes the underlying action itself.

## 10. Component model

Suggested composition:

```text
DashboardShell
  GlobalSearch
  LeftRail
    SchedulePanel
    SystemHealthPanel
    WidgetSlot(left)
    NewsPanel
  CenterStage
    QuickAppsPanel
    HeimlichPanel
      AmbientHeimlich
      ConversationHeimlich
      QuickActionGrid
  RightRail
    ModeSwitcher
    AgentList
    WidgetSlot(right)
  PersistentBottomBar
  OverlayHost
    ConfirmationWindow
    SettingsWindow
    AppMenu
    AgentWorkspace
```

Shared primitives should remain modest: panel, action button, icon button, status indicator, progress meter, list row, section heading, tooltip, popover, and overlay window. Add abstractions only when they remove real repetition or encode a stable interaction contract.

## 11. Configuration shape

Illustrative configuration contract:

```json
{
  "schemaVersion": "1.0",
  "id": "school",
  "label": "School",
  "theme": {
    "accentPrimary": "school.primary",
    "accentSecondary": "school.secondary"
  },
  "calendarProfile": "academic",
  "newsProfile": "academic",
  "quickApps": ["canvas", "drive", "claude", "gmail", "quizlet"],
  "quickActions": [
    "open_canvas",
    "review_assignments",
    "summarize_notes",
    "start_study_block",
    "open_school_folder",
    "plan_study_session",
    "capture_school_note",
    "open_school_layout"
  ],
  "widgets": {
    "left": "deadlines",
    "right": "courses"
  },
  "layoutId": "school.default"
}
```

Validation rules:

- zero to five quick apps in config; the UI always appends More Apps;
- exactly eight quick actions;
- one registered widget per free-widget slot;
- non-Executive modes include their matching layout action;
- every referenced app, action, widget, theme role, and layout has a registered identifier;
- invalid user configuration is staged with exact remediation while the last valid configuration remains active.

## 12. State and data requirements

Every networked, system, or integration-backed panel supports:

- loading;
- ready;
- empty;
- stale with timestamp;
- unavailable because capability is absent;
- disconnected or offline;
- structured error with recovery action where possible.

Updates should preserve panel geometry to prevent layout shift. Freshness, source, and last update should be accessible even when not always visible.

## 13. Responsive behavior

Target layouts include the 16-inch MacBook logical viewport, compact laptop widths, and common 1440p/4K external display arrangements.

At reduced width:

- preserve Global Search, Heimlich, mode access, and bottom-bar access first;
- collapse side rails into tabs, drawers, or one-at-a-time panels;
- keep touch/pointer targets usable;
- do not shrink the Heimlich panel below the space required for greeting, state, and actions;
- avoid horizontal page scrolling;
- allow quick actions and apps to reflow without changing their order.

External-display layouts may widen the center and side rails but should not let line lengths or control widths become excessive.

## 14. Accessibility and input

- All actions are keyboard reachable with visible focus.
- Icon-only controls have accessible names and tooltips.
- Text/background and state indicators meet appropriate contrast.
- Status never relies on color alone.
- Motion respects reduced-motion and can be disabled independently.
- Search, modal, agent workspace, and sidebar use correct focus trapping and restoration.
- Escape dismisses the topmost dismissible surface without closing CerebralHelm.
- Screen-reader announcements cover Heimlich state changes, agent completion, mode completion, and confirmation requirements without excessive chatter.

## 15. Performance budget principles

- Dashboard idle work should be minimal.
- The wave reduces frame rate or pauses when occluded or unfocused.
- System metrics use measured polling intervals and coalesce updates.
- News, calendar, market, repository, course, and media fetches are independently cached and cancellable.
- Mode switching reuses mounted shared components where practical.
- No decorative effect should block input, bootstrap, or state comprehension.
- Performance targets should be finalized through profiling on the target Mac rather than guessed in advance.

## 16. Acceptance criteria

The dashboard design is implemented correctly when:

1. All four modes render from the same shared composition and validated configuration.
2. Region placement remains stable while mode color and content change substantially.
3. Search always places `Ask Heimlich` first and can navigate apps, settings, and local CerebralHelm destinations.
4. Quick Apps supports one to five configured apps plus More Apps.
5. Heimlich ambient view has exactly eight actions in the required four-plus-four geometry.
6. Developer, School, and Entertainment expose their layout action.
7. Active conversation replaces the ambient center, provides follow-up input, and can be minimized.
8. System Health contains CPU, memory, battery, and network speed with degraded states.
9. Agents use only Idle, Waiting, Thinking, and Ready in the compact dashboard.
10. Agent identity stays fixed while mode styling changes.
11. Confirmation remains neutral blue and exposes exact action detail.
12. Layout mode adds hot-swap behavior to the bottom bar without losing Heimlich or recovery controls.
13. Fullscreen sidebar exposes the compact command environment over another app.
14. Loading, empty, stale, unavailable, disconnected, and error fixtures render without overlap or blank panels.
15. Keyboard navigation, focus restoration, reduced motion, and non-color status cues pass regression tests.
16. No dashboard component directly performs platform, provider, filesystem, or model work.

## 17. Mockup interpretation notes

The visual reference set contains eight primary plates:

1. Executive home dashboard: reference for shared composition, edge density, and four-plus-four action geometry.
2. School home dashboard: reference for academic configuration and stronger mode recoloring.
3. Entertainment home dashboard: reference for evening context, media widgets, and green palette.
4. Developer home dashboard: reference for engineering context and restrained cool palette.
5. Active Heimlich with gated action: reference for conversation replacement and modal safety.
6. Expanded Financial Advisor: reference for focused agent workspace and responsive canvas compression.
7. School layout mode: reference for managed multi-app layout, hot-swap bar, and over-app confirmation.
8. Fullscreen sidebar: reference for compact persistent access while another app owns the screen.

Where these images show `Command Center` instead of Quick Apps, omit battery from System Health, use `Online` for agents, vary the number of quick actions, or place panels differently from the region table, this specification takes precedence.
