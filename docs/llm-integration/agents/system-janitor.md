# Agent charter — System Janitor

**Status:** Proposal, 2026-08-11 — from owner's description
**Phase:** 4 (scoped agents) — see [../PLAN.md](../PLAN.md)

## It is barely an agent

The owner's framing, and it should be taken literally: **less an agent, more a set of
maintenance jobs with buttons on them.** Almost no conversational surface. Nobody
opens the System Janitor to chat; they open it to run a thing, or it runs itself.

That has an architectural consequence worth stating before anything else: this is
closer to the **existing quick-action architecture** than to the agent architecture.
Three coded actions with model judgement *inside* them, not a chat surface with tools
attached. The model is a component here, not the interface.

Its usefulness is also indirect. The other three agents produce answers the owner
wants; this one produces a knowledge base and a machine that stay in good condition —
which is only noticed when it stops happening.

## The three jobs

### 1. `file-recent-captures` — highest value

Take recent quick captures out of `inbox/` and file them where they belong in the
vault. The owner named this the highest-value job, and it is: capture is frictionless
today and filing is not, so the inbox is where notes go to be forgotten.

**This is also the most dangerous job**, because it moves the owner's durable
knowledge at scale. See *Safety* below.

Candidate for passive/background running (owner undecided) — resolved below in a way
that keeps both the passivity and the safety model.

### 2. `review-stale-notes`

Walk the vault, judge what is still relevant and what has gone stale, and **ask about
the ones it is unsure of** rather than deciding silently.

**The schema already supports this exactly.** Note metadata carries:

- `reviewAfter` — documented as "freshness boundary: after this instant the note is
  due for review"
- `status: draft | active | archived`
- and `knowledge-template/archive/README.md` already specifies the semantics:
  *"Archiving sets the note `status` to `archived` and relocates it here… **Nothing is
  deleted on archive.**"*

So this job has no new vocabulary to invent. It sets `status`, moves to `archive/`,
or sets a new `reviewAfter` — nothing else.

### 3. `system-health-report`

Deeper than the current `system.status.read`, which returns point-in-time values for
`cpu`, `memory`, `network`, `battery`, `display`. The owner wants **trends and
recommendations**: how has this behaved over time, is battery health degrading, is
some process steadily eating memory, should charging habits change.

Two gaps to close:

- **Trends need history.** Point-in-time metrics cannot answer "over the last month".
  This is the agent's SQLite state (below).
- **Battery health is not currently exposed.** The `battery` metric carries a single
  `value`. Condition, cycle count and maximum capacity — the things that justify
  "change your charging behaviour" — need adding to the system status adapter.

Emits a Report, reusing the chart block the Financial Advisor requires.

## Safety — the job that edits the vault

`file-recent-captures` and `review-stale-notes` both modify durable personal state in
bulk. CLAUDE.md is unambiguous: *never silently reset, replace or migrate user state;
every stateful change has explicit behaviour, tests, and a recovery path.*

**Rules:**

1. **Nothing is ever deleted.** Archive relocates and re-flags; it does not remove.
   Already the specified behaviour — this agent must not invent a shortcut around it.
2. **Batch confirmation, not per-note.** Forty individual prompts is confirmation
   fatigue, which trains the owner to approve without reading — the worst possible
   outcome. The existing `RiskAggregation` and `PlanHash` machinery already does
   aggregate confirmation for workflows: show the whole plan, confirm once, and let
   the hash detect if the plan changed underneath.
3. **Uncertain cases are questions, not guesses.** The owner asked for this
   explicitly. A note the model cannot confidently place stays in `inbox/` and is
   raised, rather than being filed somewhere plausible.
4. **Moves must not break links.** Obsidian wikilinks are generally name-based rather
   than path-based, so relocation is usually safe — but this needs verifying against
   the actual vault before the first bulk move, not after.

### Passive running, resolved

The owner is undecided about running `file-recent-captures` in the background. The
tension is real: passive means unattended, unattended means `modelProposed`
provenance, and that means confirmation — which is not passive.

**Resolution: background work produces a pending plan, never applied changes.** The
job runs on its own, proposes a filing plan, and leaves it waiting. The owner
approves it in one action next time they are at the dashboard. That keeps the work
passive, keeps the confirmation policy intact, and needs no exception to the safety
model.

## Staleness policy (owner, 2026-08-11)

Three signals, and they are not weighted equally.

### 1. Supersession — the strongest signal

Newer information that **conflicts with** an older note is the clearest evidence that
the older one has stopped being true. Stronger than age, because it is evidence about
the content rather than about the calendar.

**Detect it on ingest, not by scanning.** Comparing every note against every other
note for contradiction is expensive, unreliable, and would have to be redone
constantly. Instead, check only when new content enters the vault: retrieve existing
notes on the same topic and compare against those.

**There are two entry points, and the check belongs to both:**

| Entry point | When |
|---|---|
| An agent writes a note directly — usually the Research Analyst | At write |
| A quick capture lands in `inbox/` and the Janitor files it | At filing |

So this is **one shared ingest routine invoked from both paths**, not a Janitor
feature and not a Research Analyst feature. Written once, it cannot drift; written
twice, it will.

### Three outcomes, not one

"Conflicts and redundancies" are different problems with different resolutions, and
collapsing them would archive things that should have been merged:

| Relationship | Meaning | Resolution |
|---|---|---|
| **Redundant** | Says the same thing as an existing note | Merge, or link — **never** archive one as stale; nothing has been superseded |
| **Conflicting** | Contradicts an existing note | The newer supersedes: set `supersededBy`, propose archiving the older |
| **Complementary** | Related, non-overlapping | Link them; both stay |

Anything the model cannot confidently classify becomes a question, per the owner's
rule that uncertain cases are raised rather than decided.

**Record it explicitly.** A `supersededBy` frontmatter field pointing at the newer
note makes the relationship durable, inspectable in Obsidian, and auditable — the
archive decision can then be justified by a link rather than by a model's opinion at
some past moment.

### 2. Age

A solid indicator, and the cheapest. But never sufficient alone: a reference note can
be five years old and perfectly current.

### 3. Retrieval and viewing — with an important asymmetry

The owner's insight: if other agents keep pulling a note into their context, it is
demonstrably useful. That is a real signal, and it needs something that does not
exist yet — **an access log**.

Two distinct events, worth separating:

- **Agent retrieval** — the note was pulled into an agent's context. Evidence of *use*.
- **Human view** — the owner opened it. Evidence of *reading*.

> **The asymmetry that matters: retrieval saves a note; absence of retrieval does not
> condemn one.**
>
> Using retrieval frequency as a survival criterion creates a self-reinforcing bias.
> A well-titled note surfaces often and survives; a badly-titled but valuable note
> never surfaces and gets archived — so the signal measures **findability** at least
> as much as value, and archiving on its absence would quietly delete exactly the
> notes whose titles failed them.
>
> Therefore: recent retrieval **vetoes** archiving outright. Lack of retrieval is only
> ever one input alongside age and supersession, never a trigger by itself.

### The rule

Archive when **age is high AND there is no recent retrieval or view AND the note is
unlinked**, or when **something supersedes it**. Any recent retrieval vetoes. Anything
uncertain becomes a question rather than an action.

Start conservative. The cost of wrongly archiving is a note the owner has to go find;
the cost of wrongly keeping is mild clutter. Those are not symmetric.

### On deletion

Archiving is the default and effectively the only path. **The system never
hard-deletes a note** — that keeps the recovery-path guarantee in CLAUDE.md intact
and true, rather than true-with-exceptions. Deleting remains something the owner does
by hand in Obsidian, where it is unambiguously their own action.

## Persistent state — a fourth distinct shape

Worth noting across the four charters: each agent's state turned out to be a
different shape, which is a sign the architecture is fitting the problems rather than
imposing on them.

| Agent | State |
|---|---|
| Financial Advisor | Budget vs spend — plan/actual, monthly |
| Project Manager | Commitments vs delivered — plan/actual, per cycle |
| Research Analyst | **None** — vault-native |
| System Janitor | **Metrics time series** |

```sql
CREATE TABLE janitor_metric_sample (
  metric_id   TEXT NOT NULL,          -- cpu|memory|battery|network|battery_health
  sampled_at  TEXT NOT NULL,
  value       REAL NOT NULL,
  unit        TEXT,
  PRIMARY KEY (metric_id, sampled_at)
);
```

### The access log — new, and not only for this agent

The retrieval signal needs something the system does not currently record: **which
notes get used, by whom, and when.**

```sql
CREATE TABLE note_access (
  note_id     TEXT NOT NULL,
  accessed_at TEXT NOT NULL,
  accessor    TEXT NOT NULL,          -- 'user' | agent id, e.g. 'financial-advisor'
  access_kind TEXT NOT NULL,          -- retrieval | view | write
  PRIMARY KEY (note_id, accessed_at, accessor)
);
```

Three notes on it:

- **It is written by the knowledge layer, not by this agent.** Every `note.read`,
  every retrieval hit, every open. The Janitor is a *consumer* of the log, and if it
  owned the writing it would only ever see its own activity.
- **It is derived and disposable**, like the search index — losing it costs signal
  quality, never content. It should not become something the vault depends on.
- **It arrives with phase 3.** Retrieval logging has nothing to log until semantic
  retrieval exists, so this table lands with the retrieval work rather than with the
  Janitor.

### Contract change: `supersededBy`

Supersession needs a frontmatter field on note metadata, alongside the existing
`status`, `reviewAfter`, `sensitivity` and `cloudPolicy`. Pointing at the superseding
note makes the relationship durable and visible in Obsidian rather than living only
in a model's judgement at one moment in time.

Retention matters: this table grows forever if left alone, which would be an ironic
failure for the agent whose job is upkeep. Downsample beyond some horizon — the repo
already has `OperationalRetention` as a precedent.

## Tools

**Read:** `note.list`, `note.read`, `note.search`, `system.status.read`,
`janitor.metrics.history` *(new)*

**Write:** `note.archive` *(new — sets `status`, relocates to `archive/`)*,
`note.move` *(new — relocation for filing)*, `note.update.frontmatter` *(new — sets
`reviewAfter`)*

No egress. No web access. Nothing this agent does requires the internet.

## Open questions

1. ~~**What defines stale?**~~ **Decided** — see *Staleness policy* below.
2. **Does filing infer structure, or follow a declared one?** The vault has PARA-ish
   folders (`projects/`, `areas/`, `reference/`, `archive/`, `daily/`, `profile/`).
   Filing against a declared structure is predictable; inferring one is smarter and
   will occasionally invent a taxonomy the owner did not want.
3. **Cadence.** Daily for captures and monthly for stale review is the obvious split,
   but only if the pending-plan approach above is adopted.
4. **Battery health source** — `ioreg` / `system_profiler` expose condition, cycle
   count and maximum capacity. Needs a small addition to the system status adapter,
   and is a prerequisite for the recommendations the owner actually wants.
