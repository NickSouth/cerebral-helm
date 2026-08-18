# Agent charter — Project Manager

**Status:** Agreed with owner 2026-08-11
**Phase:** 4 (scoped agents) — see [../PLAN.md](../PLAN.md)

## Decisions taken (owner, 2026-08-11)

1. **Cycles mirror Linear's**, not an independent rhythm. Owner intends to shorten
   Linear cycles to **one week**, decided during implementation of this agent — so
   the cycle length must be read from Linear, never assumed.
2. **Linear becomes the single backlog for all work**, not just CerebralHelm:
   coursework, job applications, admin. Recurring homework issues are a native Linear
   feature (daily/weekly/monthly/yearly, next instance created when the previous
   reaches its due date), so this needs no custom machinery.
3. **School belongs in this agent.**
4. **Fibonacci story points**, matching the owner's existing Linear scale.
5. **The agent may write to Linear**, confirmation-gated, **including modifying active
   issues** — bounded as below.

### Consequence: the "non-Linear work" category mostly collapses

The original proposal assumed coursework and admin would live outside Linear and need
their own commitment rows. With Linear as the single backlog, nearly everything has an
identifier. `pm_commitment.source` stays for the genuinely untracked case, but
`linear` becomes the overwhelming default — and `linear.listissues` becomes the most
load-bearing new tool in the charter.

## The shape, stated up front

**A plan is a budget for time.** The Financial Advisor tracks *limits agreed* against
*money spent*, monthly, additively. This agent tracks *commitments made* against
*work delivered*, per cycle, additively. Same structure, same store design, same three
protocols. Building the second one is mostly reuse.

## Why it exists when Linear already exists

The sharpest risk with this agent is that it becomes a chat wrapper over Linear. It
earns its place only by knowing things Linear cannot:

- **Git reality** — that a branch has 14 uncommitted changes and no push
- **Calendar load** — that Thursday is gone, so "realistic" means something specific
- **Life context** — at school or at home, which changes available hours
- **Non-Linear work** — coursework, assignments, admin that never becomes a ticket
- **The owner's own cadence** — one commit-sized increment, stop for review, don't
  roll into the next issue. This is already written down in `CLAUDE.md` and is the
  single best piece of prompt context available to any agent in this system.
- **What was said versus what happened** — Linear records state, not intent over time

> **Non-duplication rule:** ticket-level truth stays in Linear. This agent's store
> holds only the planning layer Linear cannot hold, and references issues by
> identifier rather than copying them. Linear already has cycles and estimates; the
> local store must not become a second, diverging copy of them.

## The six fields

### 1. Persona

Direct, no hand-waving, and it does not pad. Reports what is true including when that
is "you committed to four things and shipped one." Proposes a next action rather than
listing options. Respects the increment discipline: it should never encourage rolling
two pieces of work together.

### 2. Domain corpus

**Deliberately thin, and possibly empty.** Generic agile/scrum/estimation literature
is low value for a single-person project, and much of it assumes a team. The
substance here is the owner's own working patterns, not external methodology.

Recommendation: **no corpus in v1.** Revisit only if a concrete question turns out to
need it. This is a useful asymmetry to record — not every agent needs one, and
assuming otherwise would add an index to maintain for no benefit.

### 3. Personal context

- `profile/` — durable facts
- **`CLAUDE.md`'s work cadence section** — the increment rule, the completion-report
  format, "don't roll into the next issue without another prompt"
- `projects/` in the vault, plus each project's `PROJECT.md` descriptor
- Prior cycle plans and outcomes from the local store

### 4. Read tools

| Tool | Source | Status |
|---|---|---|
| `linear.listissues` | `LinearAPIClient` | **New** — GraphQL query; client/auth exist |
| `repos.status` | `ActiveReposProvider` | Provider exists — branch, activity |
| `projects.list` | `ActiveProjectsProvider` | Provider exists — importance, `lastActivityAt`, descriptor |
| `calendar.list` | `CalendarProvider` | Provider exists |
| `note.search`, `note.read`, `note.list` | existing | Project notes, prior retros |

### 5. Action tools

- `linear.createissue` — exists
- `linear.updateissue` — **new**, `external_write`, confirmation-gated. May modify
  active issues, within the boundary below.
- `note.capture` — retro notes
- `plan.commit` — writes the cycle's agreed commitments, confirmation-gated

#### The write boundary: workflow metadata, never authored content

| Agent may change | Agent may not change |
|---|---|
| status, cycle, estimate (points), priority, assignee, labels | **title, description** |

The line is not risk — every one of these is confirmation-gated — it is
**authorship**. Titles and descriptions are the owner's own words; a model rewriting
them replaces thinking with paraphrase, and the loss is silent because the
confirmation prompt shows a plausible-looking replacement. Workflow metadata has no
such property: a wrong status is obvious and trivially reverted.

No egress beyond the above. Less sensitive than the Financial Advisor, but there is
no task here that needs open web search, so it does not get one.

### 6. Protocols

**1. `plan-the-cycle`** — a conversation ending in a write.

Leads with reality rather than asking what he wants to do:
- What is actually in flight (Linear open, git branches with uncommitted work)
- What is due and when
- **Calendar load across the cycle** — hours that genuinely exist
- **Context: at school or at home**
- How the last two cycles went: committed versus delivered
- Negotiates a realistic set, explicitly naming what is being left out

Writes commitments on confirmation. Delivered starts empty.

**2. `whats-next`** — ad-hoc, and the common case.

"I have two hours, what should I work on?" Weighs priority, what is already in
flight, context-switch cost, and what fits the window. Answers with **one
recommendation and its reason**, not a ranked list. Honours the increment rule:
finish and stop, do not chain.

**3. `cycle-review`** — a Report.

Committed versus delivered, cycle-over-cycle trend, where things stalled, time in
Developer mode against work shipped. Emits typed series data for the front end.
**Reuses the chart block the Financial Advisor requires** — build it once.

## Activity data comes for free

No manual time tracking. Three sources already exist:

- **`SQLiteModeSessionLog`** — time in Developer mode is already recorded
- **Git** — commits, branches, uncommitted state via `ActiveReposProvider`
- **Linear** — issue state transitions, once `linear.listissues` exists

Together these give an automatic work log. Worth stating plainly because the obvious
alternative — asking the user to log sessions — would be abandoned within a week.

## Persistent state

Same principle as the Financial Advisor: **typed domain state, not freeform agent
memory.** Same database, migration after `0016_finance.sql`.

```sql
CREATE TABLE pm_cycle (
  cycle_id         TEXT PRIMARY KEY,  -- Linear's cycle id — mirrored, never minted here
  starts_at        TEXT NOT NULL,     -- read from Linear; cycle length is NOT assumed
  ends_at          TEXT NOT NULL,
  context          TEXT,              -- school|home
  capacity_points  INTEGER,           -- agreed during planning
  notes            TEXT,
  agreed_at        TEXT
);

CREATE TABLE pm_commitment (
  cycle_id     TEXT NOT NULL REFERENCES pm_cycle(cycle_id),
  ref          TEXT NOT NULL,         -- 'NIC-204'; Linear is the default source
  title        TEXT NOT NULL,         -- denormalised for readability only
  source       TEXT NOT NULL,         -- linear|adhoc
  points       INTEGER,               -- Fibonacci: 1,2,3,5,8,13,21
  outcome      TEXT,                  -- delivered|partial|dropped|carried
  outcome_at   TEXT,
  PRIMARY KEY (cycle_id, ref)
);
```

### Points, and why velocity must be measured rather than derived

The owner's sizing intuition:

| Points | Meaning |
|---|---|
| 1 | An hour or two |
| 2 | Half a day |
| 3 | Multi-day |
| 5 | Two or three days |
| 8 | About a week |
| 13 / 21 | "Forever" — too big to plan |

**The agent must not convert points to hours.** The mapping above is deliberately
non-linear because Fibonacci encodes *uncertainty*, not duration — that is the whole
point of the scale. An agent that multiplies points by an hour figure will produce
confident, wrong capacity numbers.

Instead, **velocity is measured from history**: points delivered per cycle, summed
from `pm_commitment` where `outcome = 'delivered'`. After three or four cycles the
agent knows the real number, which is exactly what additive cycle history is for.
Before then it should say it does not know yet rather than estimate.

**A one-week cycle makes this sharp.** If cycles shorten to a week, an 8-point issue
*is* the entire cycle, and 13 or 21 cannot fit at all. That gives the planning
conversation a concrete, checkable rule: anything ≥8 points either consumes the cycle
or must be split before it can be committed to.

`title` is denormalised purely so a review reads sensibly without an API call;
Linear remains the truth for everything else about an issue.

**Cycle history is additive** — rows are never overwritten, which is what makes
"how did the last two cycles go" answerable.

## Further decisions (owner, 2026-08-11)

**One Linear team, organised by projects** — not separate teams per life area. So
`linear.listissues` filters by project, and "everything I could work on" is one
team's open issues across projects.

**Canvas owns due dates; Linear owns intent.** Deadlines are *not* duplicated onto
Linear issues — only synced if that turns out to be cheap. This removes the
two-sources-of-truth risk cleanly: when the agent needs a date it reads Canvas, and
when it needs to know what the user meant to do it reads Linear.

> **No forced matching in v1.** Recognising that Linear's "Do PS4" is Canvas's
> "Problem set 4" requires either fuzzy title matching (fragile, and wrong silently)
> or an explicit link. The agent should present deadlines and intent as two views and
> reason across both without joining them. If a join is wanted later, the durable way
> is putting the Canvas assignment id in the Linear issue — not inference.

**`whats-next` surfaces uncommitted urgent work**, and must say explicitly that it
falls outside the current cycle. Hiding it would make the agent's most-used answer
quietly wrong; presenting it silently would make the cycle plan meaningless.
