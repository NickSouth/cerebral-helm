# Quick actions — surface architecture and build plan

**Status:** In progress — phases 0-4 complete; phase 5 (pickers + streaming status) next
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

`text` · `textarea` · `select` · `multiSelect` · `number` · `datetimeRange` · `combobox` · `folderPicker`

`multiSelect` was added in phase 4 for `create-ticket`'s labels — a Linear issue routinely carries several. It renders as a checkbox list rather than a native `<select multiple>`, which needs cmd-click to add a second value and never advertises that it can hold one. Its chosen values are packed into the single string its slot in `InputValues` holds (newline-separated), rather than widening that map to `string | string[]` and rippling the change through seeding, validation and every action's submit.

`folderPicker` requires a native round trip (the `chooseFolder` bridge op) — the only field kind that does, and therefore the only one that can be *unavailable at runtime* rather than merely undrawn. It degrades to a plain text box where there is no window server. *Built in phase 4 with `git-clone`.*

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

- **Leading icons on every slot**, muted by default so the label leads. The icon takes the mode accent only while that slot's surface is open — a free, consistent open-state indicator across all 32 slots. The icon belongs in the dispatch registry beside `label` and `archetype`. *Built after phase 3; see phase 0 item 4.*
- **`shut-down` is red, and is the only differently-coloured slot.** Outline red, not filled: a solid red button reads as *danger, do not touch*, but this one is pressed on purpose. The weight belongs on the confirmation. *Built in phase 0/1 as a registry `tone` field, validated against a one-value enum so this stays the only coloured slot; a greyed placeholder never takes the tone.*
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

`project.scaffold` (folder plus template) · `youtube.search` (near-copy of `google.search`, host fixed server-side) · `app.quit` (quits **CerebralHelm itself** — the complement of `apps.quitall`, which always excludes the host; it takes no target, so neither tool can be steered into the other's territory) · a check registry plus streaming runner.

The existing hook tool returns `exitCode`, `stdout`, `stderr`, `timedOut`, and `durationMs` at completion with a 30s timeout — it cannot stream, so the live monitor needs its own capability.

### New configuration

Course-to-Obsidian-folder mapping · an optional manual course-to-event override for entries the schedule resolver cannot match (see below).

## Build order

### Phase 0 — spine

1. ~~**Dispatch registry.**~~ **Built.** `apps/dashboard/src/shell/quickActions.registry.json` — one entry per action id (`label`, `icon`, `archetype`, optional `target`), replacing the three-way split between the wiring manifest, the handler map, and the layout regex. A layout action now *declares* its mode instead of having it parsed out of the id, so the gate can check that the mode exists **and** has a layout. The slot maps above are live config, and every id a mode configures must be registered.
2. ~~**Empty-slot omit-and-recentre.**~~ **Built** in the same increment — the slot-map rewrite is what introduces the null slots.
3. ~~**Provenance confirmation tier.**~~ **Built.** `ActionProvenance` (portable core) is derived from the command envelope's source; `PolicyRequest` carries it alongside the descriptor opt-in. The NIC-133 one-off collapsed into it: `allow_external_write_without_confirmation` became `allow_external_write_when_user_authored`, so the exemption now needs both halves and an agent-proposed call to the same tool confirms. No UI, as planned.

4. ~~**Slot icons.**~~ **Built** (after phase 3, before phase 4 — it touches all 32 slots at once, so doing it while three phases of actions already existed was cheaper than revisiting each one). `QuickActionGlyph` draws the icon name each registry entry already carried: hand-authored 24×24 line paths in the same house construction as `AppGlyph`/`PanelGlyph`, inheriting `currentColor`, so no icon package and no external CDN is involved. The names follow Tabler's, so a real Tabler path can replace an entry without touching a call site.

   The glyph is muted so the label still leads, and takes the mode accent **only while that slot's own surface is open** — one comparison against `openReportId`/`openInputId` covers Reports and Inputs alike, and a slot that opens neither can never light up. The `danger` slot colours its glyph too: a red-outlined tile with a grey power icon reads as two states on one control. A `vitest` gate asserts every registered icon resolves to a drawing, closing the one seam the config gate cannot check — it can see the name is a non-empty string, but only TypeScript knows which names have paths.

### Phase 1 — free wins

~~`check-ondraft` · `open-terminal` · `start-party-mode` · `shut-down`.~~ **Built.** The first three are pure config — a URL/app reference plus a one- or two-step workflow each, dispatched through the registry's `workflow` target with no new code. `shut-down` added the `app.quit` tool (`destructive`, so it always confirms) and the `danger` slot tone.

The "matching Settings button" already existed: the pinned bottom-left shutdown control in the settings sidebar, shipped permanently disabled because no quit capability existed. It is now wired to the **same** `run shut-down` workflow as the slot rather than to a native quit, so there is one confirmation-gated path to termination instead of two doors. It stays honest-disabled off the macOS host, where `app.quit` cannot run.

### Phase 2 — report spine

**Complete.** Spine, `daily-brief` v1, `open-schedule`, and `suggest-a-movie` are all built — and the format did generalize: a flat brief, a grouped two-provider schedule, and a five-line suggestion all render through the same unchanged renderer.

- **`ReportDocument` is a contract** (`packages/contracts/schemas/reports/report-document.schema.json`), because it is the port a model will later write to. Blocks are a flat shape keyed by `blockKind`, not a discriminated union: a union makes every new block kind a breaking change, and the renderer has to survive a malformed block anyway once a model composes these. `renderableBlocks` drops any block whose kind it doesn't know or whose fields are missing, so a half-formed report renders shorter rather than blank.
- **Assemble and compose are separate functions.** `assemble` reads live providers into a typed snapshot; `compose` turns the snapshot into blocks. v2 replaces only `composeDailyBrief`.
- **`daily-brief` v1 needed no new backend.** Weather and the calendar already stream into dashboard state, so the composer runs in the web layer and the action dispatches without touching the command bus.
- **The region is the future conversation surface** — same geometry, same renderer, plus scrollback and a docked input later.

- **Action-reference params are live.** `suggest-a-movie` links out through `{action: "search-the-web", params: {query}}`, resolved via the registry and handed to the `google.search` tool, which builds the destination host-side. A reference to an unregistered or unbuilt action renders as plain text, never a control, so a model cannot mint a destination by naming one.
- **A report closes when the mode changes.** It is opened from a mode's slot and belongs to it; School's `open-schedule` left hanging in Entertainment degraded honestly but read as a bug.

Two things worth keeping:

**Codegen.** quicktype names generated types from **property** names and ignores `$defs` titles, so a generic property name mints or steals a generic type name across the whole shared module. A bare `kind` renamed the existing layout `Kind` enum and broke `LayoutWorkflowSynthesizer`; a bare `action` did the same to the mode-apply `Action`. Hence the kind-prefixed block fields (`blockKind`, `greetingSize`, `lineEmphasis`, `metricTone`, `listItems`, `reportAction`). Verify a new schema adds only additive lines to the generated files.

**The `CourseScheduleResolver` lives in the dashboard, not the portable core** — a deliberate departure from *Resolved decisions* below. The data it joins (the Canvas courses feed and the calendar region) is already in dashboard state, so putting the join in Swift would mean inventing a bridge payload for something the dashboard already holds. It moves to the core if and when the composer does. The property that actually mattered is intact: it is pure and deterministic, and an unmatched event still renders.

### Phase 3 — input spine

**Complete.** Spine, `capture-note`, and `create-event` are all built.

- **The field schema is TypeScript, not a contract** — the opposite call from `ReportDocument`, and for a reason: that one is a schema because something outside this codebase (a model) will produce one. A form is authored here, in code, per action. If a model ever proposes a pre-filled form, that is when this becomes a schema.
- **Five of seven field kinds render** (`text`, `textarea`, `select`, `number`, `datetimeRange`), plus provider-backed option sources. `combobox` (typeahead over a long list) and `folderPicker` (the only kind needing a native open-panel round trip) wait for the actions that need them. Declared-but-unrendered kinds are skipped rather than drawn broken, and a required field the renderer cannot draw never blocks a submit — the user could not fill it in.
- **`capture-note` replaced its old handler rather than sitting beside it.** The handler captured a note titled "Quick note" with an empty body because no content-entry affordance existed; two capture paths, one of which cannot carry content, is a worse surface than one.
- **A failed submit keeps the form and the typing.** Losing what someone wrote because a write failed is the worst available response to a failure.
- **Report and Input regions coexist** — different parts of the panel, and reading a brief while filling in an event is normal. A report link can open a form, so a `proposal` offering "create an event" reaches the Input region.

**`create-event` needed a new way into the bus.** No text grammar can carry a title, two datetimes, a calendar and notes without becoming lossy about quoting, so `CommandRuntime.submit(intent:source:summary:)` skips **parsing only** — the same `resolve` table owns the disclosure, and the same policy, confirmation, executor and lifecycle still run. Every later Input (`create-ticket`, `send-text`, `git-clone`, `create-project`) uses this path.

**It is also the provenance tier's first real payoff.** `calendar.createevent` is honestly `external_write`, but opts into the user-authored exemption: a person who filled in the form and pressed Create already authored exactly what happens, so re-confirming would restate what they just typed. The same call from an agent still gates, with its values disclosed. Writing is a **separate port** from reading (`CalendarWritingCapability` vs `CalendarProvider`), and the adapter asks for EventKit **write-only** access — creating an event does not require the ability to read the user's calendar.

**`create-event` writes the mode tag, because the calendar mapping alone could not carry it.** Found in review, fixed before phase 4. `CalendarRelevanceResolver` resolves an event to a mode in three layers — a `#[mode]` tag in the notes, else the calendar→mode mapping, else the default mode — and the form was writing through layer 2 only. Consequence on live settings, where exactly one calendar was mapped and it was mapped to Executive: **an event created in School did not appear in School.** It fell to Executive, whose `all` profile is the catch-all, and School's `academic` profile filtered it out. Even fully mapped, changing the Calendar dropdown silently moved the event to a different mode's schedule.

So the form carries an explicit, overridable **Mode** field defaulting to the active mode, and appends its tag to the notes on submit. Three reasons for the tag over the alternatives: it is the layer that *wins*, so the choice is honest whatever calendar the event lands in; it travels with the event, surviving an edit made later in Calendar.app or on a phone, which a local `eventId → mode` sidecar would not; and the token is the **raw mode id**, which `CalendarProfileCatalog.mode(forTag:)` already resolves directly, so no alias table is mirrored into the web layer. Mode and Calendar are deliberately independent — one decides which schedule shows the event, the other where it is stored — and the success line names both, since the tag is invisible in the schedule. This also gave `select` an `emptyOptionLabel`: a blank choice is real for a calendar (the system default) and meaningless for a mode, so it is now declared per field rather than hardcoded as "Default calendar" for every select.

Two bugs worth remembering, both found in the browser and now regression-tested: a form whose defaults depend on a persisted read must not be **built** before that read resolves (the body seeds its values once, so a late default is silently lost), and a provider-backed `select` must render its value only once the matching option exists, or the preselection is dropped when the options land.

### Phase 4 — integration-gated

Each is now "wire an integration into an existing surface", independent of the others — so they are built **one at a time, one commit each**, ordered by risk rather than by convenience. Every one of them lands on surfaces that already exist; none needs new architecture.

| # | Action | What it adds | Why here |
|---|---|---|---|
| 1 | ~~`search-youtube`~~ **Built** | `youtube.search` tool — a near-copy of `google.search`, host fixed server-side | No new integration, no credential. Warm-up. |
| 2 | ~~`git-clone`~~ **Built** | `git.clone`, narrow and typed, constrained to the projects root | New local tool, no external service. Deliberately **not** a shell-hook wrapper, which would land in the `shell` risk class and demand a confirmation on every clone. |
| 3 | ~~`create-ticket`~~ **Built** | Linear API + the first provider-backed dropdowns against a live source (teams, projects, labels) | First credential of the batch, and the first real exercise of remote option sources. Low blast radius — a ticket in your own workspace. |
| 4 | ~~`create-playlist`~~ **Built** | Spotify playlist scope | Forces **re-authorization**: the existing grant lacks the scope, so this disturbs something that currently works. Do it when you are ready to reconnect. |
| 5 | ~~`check-scoreboard`~~ **Built** | ESPN site API + the first parameterized Report + two new block kinds | Unblocked 2026-08-03 (see *Deferred to build time*). |
| 6 | ~~`send-text`~~ **Built** | iMessage send + Contacts | Highest risk in the phase: outward communication to a real person, two permission grants, and confirmation-gated with recipient and full message body disclosed. |

**1 — `search-youtube` is built.** A full vertical slice with no new architecture, exactly as predicted: two schemas, a descriptor plus its stricter-only overlay, a `YouTubeSearchCapability` port and mock, a `youtube.search` handler, a `youtubeSearch` intent and verb, a resolve case, an `NSWorkspace` adapter, and a one-field form. No credential, no bridge op, no new field kind.

The one real decision was **not** to generalize `google.search` into a host-parameterized search tool. The entire safety property of both adapters is that the destination host is a *literal constant in the adapter* — a host chosen by the caller, even from a closed set, gives that up for nothing. So the duplication is deliberate, it is stated in both adapters' doc comments, and a test asserts that a query which looks like a URL still resolves to `www.youtube.com`.

Codegen note, following the phase-2 trap: the input property is `youtubeQuery`, not `query`, and the output fields are likewise prefixed. quicktype names types from property names, and a schema structurally identical to `google-search-input` risks collapsing into one shared type. The generated diff was verified additive — zero deletions.

**2 — `git-clone` is built.** The not-a-hook decision held up, and it is what makes the action usable: `hook.run` is `shell`-class and confirms every run, while `git.clone` is one fixed executable (`/usr/bin/git`, absolute so `PATH` can never choose the binary) with a typed argument list and no shell, which is honestly `local_write` and runs one-click.

It **composes over `ProcessCapability`** rather than re-implementing process management. That adapter already guarantees an exactly-specified environment, every inherited descriptor closed, a dedicated process group so a timeout kills the whole tree, drained output, and no blocked cooperative-pool thread — all of which a second hand-rolled runner would have had to re-earn. Reusing the *runner* is not the same as reusing the `hook.run` *tool*, and only the latter would have been the mistake.

Four invariants live in the adapter, never in the caller:

- **https only.** `ssh://` and git's scp-like `host:path` reach for credentials this has no business using; `file://` would turn "clone" into a local copy tool with a caller-chosen source path.
- **A URL with embedded credentials is refused, not redacted.** A rejected token never reaches the command log; a redacted one already did.
- **Containment is re-checked after standardizing**, so a `..` in a folder name cannot place a clone outside the projects root — and an existing path is a refusal, never an overwrite. A failed clone's partial checkout is removed, so it can't masquerade as a repository in the projects widget.
- **No interactive prompt.** `GIT_TERMINAL_PROMPT=0` and no credential helper: a private repo fails fast with git's own message instead of blocking forever on a dialog nobody can see.

**Location is the parent, picked in Finder** (owner decisions, 2026-08-03). The form's location field is the plan's `folderPicker` — the one kind needing a native open-panel round trip — pulled forward from `create-project`, which now inherits it. Two calls shaped it:

- **The panel selects the parent**, and the clone lands in `<picked>/<repository name>`, the way Xcode and GitHub Desktop do it. An open panel selects folders that already exist while a clone target must not, so "pick the destination itself" would mean using New Folder on every clone.
- **Inside `~/Projects` only.** A panel can navigate anywhere, so `directoryURL` decides only where it *starts*; the selection is re-checked host-side after standardizing and resolving symlinks, and one outside the root comes back refused. That keeps the containment guarantee that lets `git.clone` run one-click. Refused and cancelled stay distinct facts — one gets an explanation, the other silence.

Two things worth keeping. The picker is the **first field kind that can be unavailable at runtime** rather than merely undrawn: it needs a window server the browser preview has no equivalent for. So the typed box is always rendered and always authoritative, the button is what disappears — a button that silently does nothing is worse than no button. And the join happens **at submit time**, so editing the URL after picking a location cannot leave a stale repository name baked into the destination; with no location the form sends nothing at all and lets the host derive the name, rather than putting the naming rule in two places that could disagree.

The `chooseFolder` bridge operation takes **no input**. A caller-supplied starting directory is the first step toward a caller-chosen destination, which is the thing the root constraint exists to prevent.

The `clone <url>` text grammar deliberately carries **no destination** — a palette command should not be able to choose where a clone lands even in principle. The form's optional folder field therefore needed a structured route, so this is the second user of `CommandRuntime.submit(intent:)` and the first new bridge operation since `createCalendarEvent`.

**3 — `create-ticket` is built.** The contract was **verified live against `api.linear.app`** rather than inferred, which mattered: a personal API key is sent as a bare `Authorization: <key>` with **no `Bearer` prefix** — the prefix is the OAuth form and would have failed. The endpoint, the `issueCreate(input:)` mutation, the `IssueCreateInput` field names, and `Issue.identifier`/`url` were all confirmed against the real workspace, the last by introspecting the input type.

Two calls diverged from what this plan expected, each because the workspace turned out not to justify the machinery:

- **`select`, not `combobox`.** Typeahead over one project and ten labels is worse than a dropdown, not better. `combobox` stays deferred until a list is genuinely long — contacts, for `send-text`.
- **Team is a field, not an inference.** There is exactly one team today, which is precisely the argument for asking: a silent "use the first team" keeps working right up until a second team exists, and then files tickets somewhere they were never meant to go. One entry in a dropdown costs a glance and buys correctness.

What *was* built beyond the plan is **`scopedBy`** — a field whose options are narrowed by another field's value. It is not decoration: a Linear project belongs to exactly one team, so a flat list would offer projects the API rejects at write time. With one team the scoping is invisible, which is exactly why it had to be built now rather than discovered later — the wrong behaviour would have been silent.

Two shapes worth keeping. The workspace is fetched **once per form open**, not once per field, because the three dropdowns are three views of one document; and it is deliberately **not cached across opens**, so a key pasted in Settings a moment ago takes effect on the next open rather than the next launch — the same lesson the Spotify Client ID taught. And reading the workspace is a **separate port** from writing an issue, the third instance of that split after calendars and the folder picker: a surface that only lists options can never reach the path that files a ticket.

**4 — `create-playlist` is built.** `POST /v1/me/playlists`, from Spotify's Web API reference. This one is **not smoke-tested**: the round trip needs a re-authorized token and would create a real playlist in a real account, so unlike Linear's read path there was no safe live check. That is stated in the adapter rather than left for someone to assume.

**The re-authorization is the whole shape of this action.** `playlist-modify-private` and `playlist-modify-public` were added to the requested scope set, which means a grant made before that still drives the now-playing widget and the playback controls perfectly and is refused for playlists. Spotify answers `403`; the adapter reports `permissionDenied`; the bridge gives it its own error code; the form says **"Spotify needs reconnecting"** rather than "something went wrong". A user whose playback still works should never be told their account is broken.

Two smaller calls. The playlist is created **empty, and then handed straight over**: seeding it means searching the catalogue and choosing from results, which is a picker with its own surface, not a field on this form. So the action opens the **desktop app** at the new playlist (`spotify:playlist:<id>`, which opens Spotify rather than a browser tab) and lets the user start adding immediately — added 2026-08-04 on the owner's ask. The open is **best-effort and can never fail the create**: the playlist exists the moment Spotify answers, and reporting a failure because a window did not come forward would be wrong about the thing that matters. The form says which happened. And it is **private unless asked otherwise**: Spotify's API defaults `public` to `true`, so omitting the field would publish to someone's profile because nobody said anything. The form asks, the adapter always sends the answer explicitly, and the confirmation discloses it in words.

Playlist creation is a **separate capability** from playback control even though both share one OAuth session — control is transport, this writes to the library, and it needs scopes control never asked for.

**`create-project` is built.** `project.scaffold` writes a folder and its `PROJECT.md`, and nothing else — no process, no network, two filesystem writes.

**A project folder is a container, not a repository**, which is the decision that shaped it. `FileSystemActiveProjectsProvider` reads projects at depth 1 and `FileSystemActiveReposProvider` finds the git repos one level *inside* them, so `git init`-ing the project folder would have produced a shape unlike every project already listed. Putting a repo in it is what `git-clone`'s location picker is for, and the two actions compose: create the project, then clone into it.

It inherits the `folderPicker` from `git-clone` with the same parent semantics and the same containment invariant. Two details worth keeping. A name containing a path separator is **refused, not sanitized** — silently turning "Helm / v2" into a nested folder would put it somewhere the user never asked for, and a name they can see is wrong beats a path they cannot. And the descriptor is **composed in code rather than substituted into `config/templates/PROJECT.md`**: that template is a hand-authoring reference full of prose placeholders, and string-replacing into prose works right up until someone edits a sentence. A test holds the generated descriptor to the template's *structure*, which survives edits to either, and another asserts the `importance` it writes survives the same frontmatter parser the widget reads with — the value is what orders the panel, so it has to parse, not merely look right.

**`email-report` and the daily brief's unread count are deferred out of this phase.** Both need Gmail OAuth, which the plan already calls the largest single lift, and which the PRD **excludes from MVP scope**. Neither belongs ahead of the tech-debt and Mac hardening/release work.

**`send-text` is built, and it settled what the provenance tier is actually for.** It shipped as `confirm_external_write` — no exemption — on the argument that a message cannot be unsent. The owner reversed that on 2026-08-04, and the reversal is right: **filling in a recipient and a message and pressing Send *is* the human's confirmation.** Re-asking restates what the user just typed, one dialog after another, for the action they perform most — which is how a confirmation stops being read. So `messages.send` takes `allow_external_write_when_user_authored` like every other write here.

Nothing about the safety story weakens. The **agent-proposed** call still gates, with the recipient, the group size and the full body disclosed — and that is the case the confirmation was ever really for. "Ask before all actions" still re-arms it. The disclosure still says `reversibility: not_reversible`, because that is simply true. What changed is *who is shown it*, which is the entire point of separating risk from provenance.

The general rule, now demonstrated rather than asserted: **irreversibility is not by itself a reason to confirm a user-authored action.** `destructive`, `financial` and `purchase_or_booking` remain unexemptible because the *class* is; an irreversible `external_write` the user composed by hand is not in that set.

**The body is disclosed in full, `sensitive: false` — deliberately.** Marking it sensitive would render it as `•••••• (hidden)`, blanking the one thing worth re-reading. Sensitivity protects a value from the **log**, which is what the descriptor's `redactionPaths: ["/messageBody"]` does; the confirmation is the user reading their own message. Different jobs, and this is the action that makes the difference obvious.

**Injection safety is the adapter's whole shape.** The message is passed to `osascript` as an **argument** against a fixed `on run argv` script — verified — so a body containing quotes, `&`, or the literal `end tell` is data. Interpolating it into script text would have made every message the user types an AppleScript injection into their own Messages app. A test asserts the script never contains the body.

`combobox` finally arrived, and only here: typeahead over an address book earns itself, where typeahead over Linear's ten labels would have been worse than a dropdown. **Nothing is chosen until a result is clicked** — typing only filters — so a half-typed name can never become a recipient.

Reading recipients is a **separate port** from sending, the fourth instance of that split and the one where it matters most. Contacts and Automation are refused independently, and a refusal drops that source rather than failing the read: a contact list with no group threads is still usable.

**`send-text` design note (verified 2026-08-03 against the Messages scripting dictionary on this Mac).** `send … to` accepts a **chat** as well as a participant, and `chat` exposes `id`, `name` and `participants`, so messaging an **existing group thread is supported**. There is no creation command — `chats` is read-only — so a *new* group cannot be assembled from a set of contacts. Two consequences: the recipient source is **contacts plus existing chats**, and the confirmation disclosure should name the resolved recipient *and*, for a group, its size — sending to a thread of nine is a materially bigger action than sending to one (FR-SAF-04). The API surface was verified, not an end-to-end send; that needs an Automation grant and is a manual step.

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
3. A manual override, for entries nothing else catches.

*As built, the override is checked **first**, not last: an override that only applied to unmatched events could never correct a wrong match, which is most of what an override is for. The mechanism and its tests exist; populating it from config does not, so it is currently always empty. Name-token matching ignores generic words (`lecture`, `lab`, `fall`, `introduction`) so they can never drive a match.*

Two rules that keep this honest. The resolver is **deterministic and testable** — no model, no fuzzy scoring that drifts between runs. And an **unmatched event still renders**, in an ungrouped section, rather than disappearing: a schedule that silently drops a class is worse than one that shows an unattributed entry.

Bullet colour comes from the **course**, not the calendar, so a course keeps one colour even when its lecture and its final live on different calendars.

**Report region width may grow to 40%** when content demands it, rather than staying a hard third.

## Deferred to build time

**Sports API choice — decided 2026-08-03: ESPN's undocumented site API.** `site.api.espn.com/apis/site/v2/sports/football/nfl/scoreboard` and `.../golf/pga/scoreboard`, both 200 unauthenticated with no key, both probed live before this was written.

This **overrides the criterion above**, knowingly: the endpoints are undocumented and can change without notice. Nothing else free covers both a team sport and an individual leaderboard, and a shape change is survivable if the mapper degrades rather than throws. That is the trade, stated once so nobody re-litigates it later.

What the probes established:

- **NFL is 17 KB.** Each event carries `shortName`, `status.type.{state, shortDetail, completed}`, `status.period`/`displayClock`, and per-competitor `homeAway`, `score`, and team `abbreviation` / `color` / `logo` / `records`. The hex colour arrives in the same payload, which is why teams render as **colour + abbreviation** and no logo fetch is needed (owner decision; the logo URLs would each need a data-URI round trip under the webview's CSP, like the Spotify artwork).
- **Golf is 1.2 MB, unavoidably.** `/leaderboard` 404s and `?limit=` is ignored. Fine for an on-demand fetch that the host trims before anything crosses the bridge; it rules out polling on a widget cadence. Hence **snapshot + manual refresh** (owner decision) rather than a live publisher.
- **The in-progress shape is unverifiable until a tournament is live.** On a `Final` event `position` and `thru` come back empty, so the live-round rendering is written against the documented field names and confirmed in season.

`check-scoreboard` is therefore a **Report opened from an Input** — a picker of up to three active events, then a composed report. Owner decision: **top 10, expandable to the full field**.

Three surface extensions it needs, none of them ESPN-specific:

1. **Reports become parameterizable.** `ReportProvider` holds one id and composers read ambient dashboard state; this one is opened *with* the chosen event ids.
2. **An Input whose submit opens a Report** — the symmetric direction of the `ActionLink` that already opens an Input from a report.
3. **A `scoreboard` and a `leaderboard` block kind**, plus the scroll treatment the Input region already has. Exactly the additive change the flat block shape exists to absorb.

**Increment 1 is built**: the provider, the `listSportsEvents` read, the picker, and reports that carry arguments — composed with the block types that already exist, so the data can be judged before any effort goes into how it looks. Three things worth keeping from it.

`openReport(id, params)` **re-opens rather than toggles when the arguments change**. Every other slot toggles its own report closed on a second press, which is right for a parameterless one; picking a different set of games and pressing Show has to render them, not close the panel.

**One cached fetch serves the picker and the report.** They read the same document — the picker shows the names, the report shows the detail already inside them — so a module-level cache with a 60-second life stops each use from paying golf's megabyte twice. The *promise* is cached rather than its result, so the report joins the picker's in-flight request instead of starting a second; and a failure is never cached, so the next attempt can succeed. The window is deliberately short: a cache long enough to hide a score change would make the report quietly wrong, which is worse than slow.

**The picker orders rather than filters.** Live events come first, then scheduled, then finished — but nothing is hidden, because "nothing is live right now" is the normal state for most of the year and an empty picker all summer reads as broken rather than as out of season.

`sportsEvents` is the **second** bespoke remote option source in the Input region, alongside Linear's. A third is the point to collapse them into one provider-registry hook rather than write another one-off.

**Increment 2 is built**: the `scoreboard` and `leaderboard` block kinds, the expand-to-full-field control, and the refresh.

The **leaderboard block carries the complete field with a `leaderboardPreview` count**, so expanding is a render decision rather than a second megabyte — a block that held only ten rows could not expand at all. That is the shape any future paginated block should copy.

**Team colour is a thin accent bar, not a fill.** A tile flooded with team colour would be the loudest thing in a dashboard built on one accent per mode, and the report's own rule is that colour means *actionable*. A bar reads as identity without pretending to be a link; a team with no colour keeps the bar, unpainted, so the rows still line up.

**`refreshable` is declared by the document, not assumed by the region.** Only a report composed from a fetch can honestly offer to repeat it — showing the control on a document built from ambient state would promise something it cannot do.

`venue` is carried through even though only NFL supplies it, and even though nothing but one muted line renders it today. That is deliberate: **the assemble stage should hold more than the renderer needs**, because the reader after the renderer is a model. Golf's payload has no course at all, which is the concrete case — "what course is this?" genuinely needs another source, and the report says nothing rather than inventing one.

## Design spec edits owed

Three places where [the design spec](../../.agent/spec/CEREBRALHELM_DESIGN_SPEC.md) contradicts this plan. Each is corrected in the increment that makes it false, not up front:

1. **§5.7** describes the conversation surface as a translucent overlay with semi-transparent bubbles over a scrim. This plan uses an opaque, borderless region with a right-edge fade — which also satisfies the contrast requirement outright rather than fighting for it. *Owed in phase 2, with the Report region.*
2. ~~**Acceptance item 5** requires "exactly eight actions in the required four-plus-four geometry".~~ **Done in phase 0:** the quick-action geometry section, acceptance item 5, and the UI Constitution's always-8 rule now describe omit-and-recentre.
3. **The Input region is not described at all.** It needs a section alongside the ambient and conversation views. *Owed in phase 3, with the Input region.*

## Related

- [ADR-003 — internal tool registry and risk policy](../adr/ADR-003-internal-tool-registry-and-risk-policy.md): descriptors are authoritative; the provenance tier extends this without weakening it.
- [ADR-002 — single command lifecycle](../adr/ADR-002-single-command-lifecycle.md): every action still resolves through one bus.
- [MVP PRD](../../.agent/spec/MVP-PRD.md): FR-MOD-02/03/04, FR-SAF-02, FR-CFG-04, FR-UI-09.
