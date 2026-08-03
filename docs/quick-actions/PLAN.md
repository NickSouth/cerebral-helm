# Quick actions — surface architecture and build plan

**Status:** In progress — phase 0 complete (dispatch registry, omit-and-recentre, provenance tier); phase 1 next
**Owner:** Nick Southey
**Source:** Planning session 2026-08-03; supersedes the NIC-139 workflow-builder approach
**Scope:** All 32 quick-action slots across the four modes, the surfaces they render in, and the order to build them

## Why this document exists

The eight quick-action slots per mode were placeholder ids with no implementation — 28 of 32 rendered as disabled "coming soon" tiles. This plan specifies what each slot does, the small set of shared surfaces they all render through, and a build order that puts the shared foundations before anything that depends on them.

The governing constraint is coherence: 20 distinct actions built from **four archetypes**, **two in-dashboard surfaces**, and **one document format** — not 20 bespoke screens.

## Decision: hardcode the actions, park the workflow builder

NIC-139 proposed a settings workflow builder that would author quick actions as chains of registered tools. It is **parked**, by owner decision, for two reasons discovered during planning:

1. Most desired actions need **bespoke interactive UI** (a form, a live monitor, a rich report). A visual builder that composes static-input tool calls can never author those, and extending it to try would reintroduce the branching and inter-step data flow that were already cut from its scope.
2. The builder's stated value was customization without modifying the codebase — but the repository owner is the only user, so hardcoding is a file edit.

The builder's addressable surface was therefore the smallest and least interesting slice of the list. Its planning work is not wasted: the per-tool input field catalog it required became the Input field schema below.

**Corollary rule:** the boundary that keeps this simple is that composed-tool actions and coded-surface actions stay separate kinds. An action needing its own UI is coded, permanently.

## Archetypes

Every action is exactly one of four:

| Archetype | Shape | Count |
|---|---|---|
| **Input** | Form collects values, invokes a tool | 11 |
| **Fire-and-forget** | Dispatch, no surface; result on the status line | 7 |
| **Report** | Assemble from providers, render a document, offer follow-up actions | 6 |
| **Picker** | Filterable list, options from a provider, one action on selection | 2 |

**Live Monitor is not an archetype.** A streaming status list is a Report whose document is re-emitted as state changes — same renderer, plus a `checklist` block. Only its host differs (an external window rather than the centre panel).

**Picker is not a distinct surface.** A picker's result almost always opens an external app, so nothing needs to persist. It renders in the Input region with a filter field, a result list, and the same footer.

## Surfaces

| Surface | Location | Used by |
|---|---|---|
| **Report region** | Centre panel, left third — below the Heimlich label, down to above the greeting. Opaque, borderless, right-edge mask so the consciousness stream dissolves into it. | Reports, and later the Heimlich conversation |
| **Input region** | Centre panel, lower right — below the stream, above the quick-action grid. Bordered panel (it is interactive and needs a hit target). | Inputs and Pickers |
| **External window** | Own native window | `system-status-checks` only |

The Report region **is** the future chat surface: same geometry, same renderer, plus scrollback and a docked input. Design spec §5.7 already describes that conversation overlay; see *Design spec edits owed* below.

## The report document format

The single most consequential decision in this plan. A report is **not a template** — it is a typed document, because an LLM will eventually compose it.

```text
providers --> Assembler --> Snapshot --> Composer --> ReportDocument --> Renderer
              deterministic  typed data  editorial     blocks            fade + reveal
```

- **v1:** the Composer is deterministic — the formula, in code.
- **v2:** an LLM is the Composer. Same input type, same output type.
- **The Renderer never changes** — not when the LLM lands, not when chat lands.

A model streaming tokens into the renderer is visually identical to the deterministic reveal, which is why chat is not a new surface.

### Block types

| Block | Carries |
|---|---|
| `greeting` | text, size role |
| `line` | text, emphasis |
| `metric` | label, value, tone |
| `list` | items, each with text, colour, meta |
| `checklist` | items, each with a status (pending, running, passed, failed) — the streaming variant |
| `empty` | text |
| `count` | value, label |
| `proposal` | prose plus action references |

### Action references

Any span, list item, or standalone block may carry an action reference. It is **never a URL** — it is `{action, params?}` resolved through the dispatch registry.

Two reasons this is non-negotiable. Opening a destination in a specific Chrome profile is a profile-scoped reference (NIC-151), not an href. And once a model composes the document, every clickable thing in it is a model-chosen destination — a raw href would let an LLM, or content it summarized, point anywhere.

Params from a model are untrusted, so the **tool constructs the destination host-side**, following the pattern the `google.search` input schema already establishes: the host is fixed, only the query varies, so untrusted data can never choose the destination. A `gmail.openMessage` tool takes a message id and builds the URL itself.

This unifies with the `proposal` block — an inline link and a proposed follow-up are one mechanism in three placements, not two features.

## The input field schema

An Input is `{title, fields[], submitAction}`. Seven field kinds cover every planned action:

`text` · `textarea` · `select` · `number` · `datetimeRange` · `combobox` · `folderPicker`

`folderPicker` requires a native round trip (an open-panel bridge op) — the only field kind that does.

`select` and `combobox` take a **source** that is either a static list or a **provider id**. One mechanism serves four actions: calendars for `create-event`, contacts for `send-text`, projects and labels for `create-ticket`, courses for `take-notes`.

**Mode-aware defaults, not per-slot parameters.** `create-event` appears in all four modes with a different default category. The category *is* the active mode, so the action reads it at render time: one id, one registration, correct default everywhere, no contract change. Do not build a per-slot parameter mechanism until something actually requires one.

## Confirmation: the provenance tier

A third permission dimension, decided during planning. Risk describes what an action does; **provenance** describes who determined its arguments.

- **Risk** stays a property of the tool. Unchanged.
- **Provenance** is a property of the invocation: `user_authored` or `model_proposed`.
- **The policy key** declares whether a tool honours a user-authored exemption.

Provenance must be **derived by the runtime from the command source, never supplied by the caller**. A caller-supplied field would let a model claim `user_authored`, which is precisely the bypass FR-SAF-02 exists to prevent.

| Scenario | Provenance | Confirms |
|---|---|---|
| User types a message and presses send | `user_authored` | no |
| User presses an action whose arguments they authored earlier | `user_authored` | no |
| User says "book it near noon", model picks 12:15 | `model_proposed` | **yes**, disclosing 12:15 |

Hard guardrails: `destructive`, `financial`, and `purchase_or_booking` are never exemptible regardless of provenance, and the existing "ask before all actions" setting still re-arms everything.

This generalizes the one-off exemption NIC-133 introduced for the Spotify widget controls, which **has** collapsed into the general rule (phase 0). The descriptor key `allow_external_write_without_confirmation` became `allow_external_write_when_user_authored`: the same tool that runs one-click for the user now confirms when an agent proposes the call, which the unconditional waiver did not do.

## Visual rules

- **Leading icons on every slot**, muted by default so the label leads. The icon takes the mode accent only while that slot's surface is open — a free, consistent open-state indicator across all 32 slots. The icon belongs in the dispatch registry beside `label` and `archetype`.
- **`shut-down` is red, and is the only differently-coloured slot.** Outline red, not filled: a solid red button reads as *danger, do not touch*, but this one is pressed on purpose. The weight belongs on the confirmation.
- **Accent colour means actionable** inside a report. Emphasis without a target uses weight or a lighter neutral. One meaning per colour, and it scales to whatever a model writes later.
- **Empty slots are omitted, not rendered as placeholders.** Remaining slots re-centre within their row, preserving the bar/box split. Nulls stay in config; only the renderer changes.
- **Reports reveal top-down on a stagger**, block by block, as the background fades in and the stream eases aside. Block-level rather than character-level reads better at this density and maps directly onto streamed tokens.
- **The ambient greeting hides while a report is open**, so the report's own greeting does not stack against it.
- Links must be keyboard reachable with a visible focus ring (FR-UI-09).

## Slot maps

Bars are slots 0-3, boxes 4-7. `create-event` sits at slot 2 in every mode.

### Executive

| Slot | Action | Archetype | Icon |
|---|---|---|---|
| 0 | `daily-brief` | Report | file-text |
| 1 | `capture-note` | Input | notes |
| 2 | `create-event` | Input | calendar-plus |
| 3 | `create-project` | Input | folder-plus |
| 4 | `send-text` | Input | message |
| 5 | `email-report` | Report | mail |
| 6 | `system-status-checks` | Report (streaming) | activity |
| 7 | `shut-down` | Fire-and-forget | power |

### Developer

| Slot | Action | Archetype | Icon |
|---|---|---|---|
| 0 | `open-developer-layout` | Fire-and-forget | layout-grid |
| 1 | `git-clone` | Input | git-branch |
| 2 | `create-event` | Input | calendar-plus |
| 3 | `create-ticket` | Input | ticket |
| 4 | `check-ondraft` | Fire-and-forget | external-link |
| 5 | `open-terminal` | Fire-and-forget | terminal-2 |
| 6-7 | reserved | — | — |

### School

| Slot | Action | Archetype | Icon |
|---|---|---|---|
| 0 | `open-school-layout` | Fire-and-forget | layout-grid |
| 1 | `open-schedule` | Report | calendar |
| 2 | `create-event` | Input | calendar-plus |
| 3 | `take-notes` | Picker | notes |
| 4 | `search-notes` | Picker | search |
| 5-7 | reserved | — | — |

### Entertainment

| Slot | Action | Archetype | Icon |
|---|---|---|---|
| 0 | `open-entertainment-layout` | Fire-and-forget | layout-grid |
| 1 | `create-playlist` | Input | playlist |
| 2 | `create-event` | Input | calendar-plus |
| 3 | `search-youtube` | Input | brand-youtube |
| 4 | `check-scoreboard` | Report | ball-football |
| 5 | `suggest-a-movie` | Report | movie |
| 6 | `start-party-mode` | Fire-and-forget | disco |
| 7 | reserved | — | — |

Six reserved slots are held for the LLM era — a coding-agent surface, note summarization, study-guide generation. They are built as the need arises, not pre-specified.

## Capability inventory

### Free — no new capability

`check-ondraft` (URL reference with a Chrome profile; pure config) · `open-terminal` · `start-party-mode` · `capture-note` · `open-schedule` · `search-notes` (lexical today) · `suggest-a-movie` · `take-notes` (needs only a course-to-folder mapping)

Eight of twenty compose capabilities already shipped.

### New external integrations

| Integration | Unlocks | Notes |
|---|---|---|
| Gmail read (OAuth) | `email-report`, `daily-brief` unread count | Excluded from MVP scope by the PRD; the largest single lift |
| EventKit **write** | `create-event` in all four modes | Read side already exists |
| iMessage send + Contacts | `send-text` | AppleScript into Messages; two permission grants |
| Linear API | `create-ticket` | Field options fetched remotely |
| Spotify playlist scope | `create-playlist` | Forces re-authorization — the current grant lacks it |
| Sports API | `check-scoreboard` | Verify a specific API's contract before committing |

### New local tools

`git.clone` — narrow and typed, constrained to the projects root. Deliberately **not** a shell-hook wrapper, which would land in the `shell` risk class and demand a confirmation on every clone.

`project.scaffold` (folder plus template) · `youtube.search` (near-copy of `google.search`, host fixed server-side) · `app.quit` · a check registry plus streaming runner.

The existing hook tool returns `exitCode`, `stdout`, `stderr`, `timedOut`, and `durationMs` at completion with a 30s timeout — it cannot stream, so the live monitor needs its own capability.

### New configuration

Course-to-Obsidian-folder mapping · an optional manual course-to-event override for entries the schedule resolver cannot match (see below).

## Build order

### Phase 0 — spine

1. ~~**Dispatch registry.**~~ **Built.** `apps/dashboard/src/shell/quickActions.registry.json` — one entry per action id (`label`, `icon`, `archetype`, optional `target`), replacing the three-way split between the wiring manifest, the handler map, and the layout regex. A layout action now *declares* its mode instead of having it parsed out of the id, so the gate can check that the mode exists **and** has a layout. The slot maps above are live config, and every id a mode configures must be registered.
2. ~~**Empty-slot omit-and-recentre.**~~ **Built** in the same increment — the slot-map rewrite is what introduces the null slots.
3. ~~**Provenance confirmation tier.**~~ **Built.** `ActionProvenance` (portable core) is derived from the command envelope's source; `PolicyRequest` carries it alongside the descriptor opt-in. The NIC-133 one-off collapsed into it: `allow_external_write_without_confirmation` became `allow_external_write_when_user_authored`, so the exemption now needs both halves and an agent-proposed call to the same tool confirms. No UI, as planned.

Icons are carried in the registry but not yet rendered — the Tabler glyphs need vendoring (no external CDN), which belongs with the visual pass, not the dispatch spine.

### Phase 1 — free wins

`check-ondraft` · `open-terminal` · `start-party-mode` · `shut-down` (needs `app.quit` plus the matching Settings button).

### Phase 2 — report spine

Report region, `ReportDocument`, and the renderer, then `daily-brief` v1 — time, weather, calendar; the unread count arrives with Gmail. Follow with `open-schedule` and `suggest-a-movie` to prove the format generalizes across three very different reports.

Riskiest design decision, validated before anything depends on it.

### Phase 3 — input spine

Input region, field schema, field kinds, provider-backed option sources. Then `capture-note` (a single textarea — the simplest possible instance), then `create-event` (multi-field, external write, provider-backed dropdown, four modes — the real stress test).

### Phase 4 — integration-gated

Each is now "wire an integration into an existing surface", independent of the others: `git-clone`, `create-project`, `search-youtube`, `create-ticket`, `send-text`, `create-playlist`, `check-scoreboard`, `email-report`, and the daily brief's unread count.

### Phase 5 — lowest reuse, last

Picker (two instances) for `take-notes` and `search-notes`. Streaming report plus external window for `system-status-checks`.

## Deferred by design

Several actions ship a deterministic version now behind a surface that does not change when the richer version lands:

| Action | v1 | v2 |
|---|---|---|
| `daily-brief` | Formula: time, weather, calendar, unread count | LLM composes prose and proposes follow-ups |
| `search-notes` | Lexical search | Semantic — swap the search provider only |
| `suggest-a-movie` | Trending title, release date, description | Personalized; **requires a watch-history source that does not exist** |
| `start-party-mode` | Open Spotify and the ambient video | Speaker targeting, playlist, smart lights |

News and stock sources are **dropped** from the daily brief formula. Both remain live providers, so feeding them to a future LLM composer to include when relevant is cheap.

## Resolved decisions

**`open-schedule` groups by Canvas course, matched against calendar entries.** Canvas is the authoritative course list (already scraped); the calendar is the authoritative source of meeting times and finals. A deterministic `CourseScheduleResolver` in the portable core joins them, alongside the existing calendar relevance resolver.

The join key is the **course code**, not the full name — Canvas titles like `STAT 240 - Introduction to Probability and Statistics (Fall 2026)` will never string-match a calendar entry reading `STAT 240` or `Stats lecture`. So:

1. Extract a course code (`[A-Z]{2,4}\s?\d{3}`) from both sides and match on it, normalized.
2. Fall back to token overlap against the course name.
3. Fall back to the manual override in config, for entries nothing else catches.

Two rules that keep this honest. The resolver is **deterministic and testable** — no model, no fuzzy scoring that drifts between runs. And an **unmatched event still renders**, in an ungrouped section, rather than disappearing: a schedule that silently drops a class is worse than one that shows an unattributed entry.

Bullet colour comes from the **course**, not the calendar, so a course keeps one colour even when its lecture and its final live on different calendars.

**Report region width may grow to 40%** when content demands it, rather than staying a hard third.

## Deferred to build time

**Sports API choice** (`check-scoreboard`, phase 5). No decision is needed now and an early one would go stale. When it comes up, the criteria are: a documented contract with a stated free tier beats a widely-used but undocumented endpoint that can change without notice; coverage must include both team schedules/scores and individual-event leaderboards, since NFL and PGA are structurally different; and it must be reachable without a paid plan for personal use. Verify the actual contract before writing the provider — never infer endpoint shapes.

## Design spec edits owed

Three places where [the design spec](../../.agent/spec/CEREBRALHELM_DESIGN_SPEC.md) contradicts this plan. Each is corrected in the increment that makes it false, not up front:

1. **§5.7** describes the conversation surface as a translucent overlay with semi-transparent bubbles over a scrim. This plan uses an opaque, borderless region with a right-edge fade — which also satisfies the contrast requirement outright rather than fighting for it. *Owed in phase 2, with the Report region.*
2. ~~**Acceptance item 5** requires "exactly eight actions in the required four-plus-four geometry".~~ **Done in phase 0:** the quick-action geometry section, acceptance item 5, and the UI Constitution's always-8 rule now describe omit-and-recentre.
3. **The Input region is not described at all.** It needs a section alongside the ambient and conversation views. *Owed in phase 3, with the Input region.*

## Related

- [ADR-003 — internal tool registry and risk policy](../adr/ADR-003-internal-tool-registry-and-risk-policy.md): descriptors are authoritative; the provenance tier extends this without weakening it.
- [ADR-002 — single command lifecycle](../adr/ADR-002-single-command-lifecycle.md): every action still resolves through one bus.
- [MVP PRD](../../.agent/spec/MVP-PRD.md): FR-MOD-02/03/04, FR-SAF-02, FR-CFG-04, FR-UI-09.
