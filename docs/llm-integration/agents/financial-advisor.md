# Agent charter — Financial Advisor

**Status:** Drafted 2026-08-11, decisions taken with owner
**Phase:** 4 (scoped agents) — see [../PLAN.md](../PLAN.md)

## What it is

Not a question-answering surface over bank data. **A place to manage spending**,
which happens to be conversational (owner, 2026-08-11). The difference is state: it
remembers the budget, tracks spend against it across the month, and knows how far it
has already looked.

The question it must answer:

> "Do I have $100 left in my budget this month to make this purchase?"

Worth separating, because it drove everything below: **this is a budget question,
not a bank question.** Balances say what money exists, never what it is spoken for.

## The six fields

### 1. Persona

Frames rather than prescribes. States the arithmetic and the assumptions, and names
its own uncertainty. Never presents itself as a licensed advisor. Allocation
*frameworks* are in scope; individual stock picking is not.

### 2. Domain corpus

Target subjects, from the owner: savings rates appropriate to age, market
volatility, risk assessment, allocation.

**Recommended spine — US federal sources, public domain** under 17 U.S.C. § 105:

| Source | Covers |
|---|---|
| investor.gov (SEC) | Investing basics, risk, diversification, fees |
| consumerfinance.gov (CFPB) | Budgeting, debt ordering, credit |
| IRS Pub 590-A / 590-B | IRA contribution and distribution rules |
| IRS Pub 969 | HSAs |
| SSA publications | Retirement timing |

Authoritative, stable, and freely redistributable. **Caveat:** not everything on a
`.gov` is a government work — contractor and licensed third-party content appears
there too, so verify per document rather than assuming the domain.

**Secondary — the Bogleheads wiki, GFDL.** Reusable with attribution and share-alike.
Better practical guidance on exactly the "how much should someone my age be saving"
questions than the federal material. GFDL is copyleft: harmless for local personal
use, relevant if CerebralHelm is ever distributed.

Excluded: securities analysis and market commentary. Low signal, ages badly.

### 3. Personal context

- `profile/` — durable facts
- A finances slice in its own note, carrying its own `sensitivity` and `cloudPolicy`
- The budget note (below), which is both context and data

### 4. Read tools

| Tool | Source | Notes |
|---|---|---|
| `finance.accounts` | SimpleFIN | Balances across all four institutions |
| `finance.positions` | SimpleFIN | E*TRADE holdings — owner wants position-level, not just balances |
| `finance.transactions` | SimpleFIN | **Watermark-aware**, see below |
| `budget.read` | SQLite + note | Returns TYPED categories, limits, spend-to-date |
| `stocks.quote` | existing `StockQuoteProvider` | Already built |
| `market.news` | Finnhub / existing `NewsProvider` | **Ticker-keyed only** — see the egress rule |
| `note.search`, `note.read` | existing | Decision history |

### 5. Action tools

- `note.capture` — log a decision ("deferred the purchase, revisit in September")
- `budget.update` — write category limits, confirmation-gated

**No egress tools, by rule.** No `messages.send`, `web.open`, `url.open`,
`hook.run`, `google.search`.

### 6. Protocols

Three are **pre-baked quick actions** the user launches by name (owner spec,
2026-08-11). They map onto existing quick-action archetypes rather than needing new
surfaces: the first two are conversations, the third is a Report.

**1. `make-months-budget`** — a conversation, ending in a write.

The agent leads; it does not ask for a number and stop. It works through:
- Any big purchases or one-offs planned this month
- Last month's actuals, by category
- Income expected this month
- **Context: at school or at home** — the owner's spending pattern differs
  materially, so this is a first-class field on the month, not small talk
- Trends across previous months
- Realistic targets, negotiated

Concludes with an agreed set of category limits, written to the month's rows on
confirmation. Actual spend starts empty and accrues from transactions.

**2. `investment-advice`** — a conversation.

Reads existing positions (E*TRADE, live), asks how much is being invested and into
which account, then lays out options against current market data and the corpus's
frameworks. Presents tradeoffs and the reasoning, not a single instruction — the
version that stays useful when it turns out to be wrong.

**3. `financial-analysis`** — a Report.

Reads spending history and income, emits **typed series data** for the front end to
draw. Trends over time, spend by category, budget-versus-actual, income-versus-spend.
The agent produces data; the renderer produces graphs.

Plus the ad-hoc path, which is the common case:

**`can-i-afford-this` / spend check** — "I'm going grocery shopping, what's my budget
this week?" Syncs new transactions since the watermark, updates spend-to-date, and
answers against the remaining category limit — never from balance alone. Weekly
figures are derived (remaining ÷ weeks left), not stored.

## Persistent state — the architecture

The owner's insight: the agent should accumulate state rather than re-derive
everything per question. Two stores, split on a principle that matters.

**Typed domain state, NOT freeform agent memory.** A model writing notes to itself
is where hallucinations get persisted and compound; nothing downstream can tell a
remembered fact from an invented one. Everything the agent retains is typed,
inspectable, and correctable by hand — consistent with the repo rule that durable
state stays local, inspectable, portable and migration-safe.

The North Star already assigns finances to SQLite: *"structured data for tasks,
habits, finances, logs, calendar metadata, tool usage, mode history."*

**Same database, new migration `0016_finance.sql`** — not a separate file. The repo
runs one SQLite database through numbered migrations with an existing
`BackupService` and `BackupRetention`; a separate file would need its own migration
runner, backup and retention. (If finances should be excludable from backups
independently, that argues for a separate file — flagged, not decided.)

**Budget history is additive.** Rows are keyed by month and never overwritten, so
past budgets stay queryable — which is what makes trend analysis and "what did we
agree last month" possible.

### Schema sketch

```sql
CREATE TABLE finance_account (
  account_id      TEXT PRIMARY KEY,   -- SimpleFIN account id
  institution     TEXT NOT NULL,
  display_name    TEXT NOT NULL,
  account_type    TEXT NOT NULL,      -- checking|savings|credit|brokerage
  last_synced_at  TEXT                -- THE WATERMARK
);

CREATE TABLE finance_transaction (
  transaction_id  TEXT PRIMARY KEY,   -- SimpleFIN id: makes re-sync idempotent
  account_id      TEXT NOT NULL REFERENCES finance_account(account_id),
  posted_at       TEXT NOT NULL,
  amount_cents    INTEGER NOT NULL,   -- negative = spend
  description     TEXT NOT NULL,
  category        TEXT,
  category_source TEXT,               -- rule|user|model
  source          TEXT NOT NULL,      -- simplefin|manual
  imported_at     TEXT NOT NULL
);

CREATE TABLE finance_month (
  month                 TEXT PRIMARY KEY,  -- '2026-08'
  context               TEXT,              -- school|home
  income_expected_cents INTEGER,
  income_actual_cents   INTEGER,
  notes                 TEXT,
  agreed_at             TEXT               -- when the budget conversation concluded
);

CREATE TABLE finance_budget_category (
  month       TEXT NOT NULL REFERENCES finance_month(month),
  category    TEXT NOT NULL,
  limit_cents INTEGER NOT NULL,
  note        TEXT,
  PRIMARY KEY (month, category)
);
```

**Spend-to-date is a VIEW over transactions, not a stored column.** The owner
described writing "actual spend" on each check; the same behaviour falls out of
summing transactions, and it cannot drift, be double-counted, or disagree with the
underlying data. "Starts null" is then a property of having no transactions yet
rather than of an empty column.

**Transactions are stored in full, not just aggregates.** Two reasons, both
load-bearing:

1. `financial-analysis` needs transaction granularity to plot anything.
2. Categories can be revised later and everything recomputes.

**Consequence worth acting on: history only exists going forward.** SimpleFIN serves
a 90-day maximum window, so trends beyond roughly three months exist only if this
database has been accumulating them. **Starting the sync early has standalone value,
before any agent work is finished.**

**Cash is a real gap.** Spending that never touches a linked account is invisible to
SimpleFIN, which is why `finance_transaction.source` distinguishes `manual` — the
user (or the agent, on confirmation) can record "$40 groceries, cash" so the budget
stays honest.

**Positions are not stored.** E*TRADE holdings are read live; caching them would add
a staleness problem for no benefit.

**The watermark is not an optimisation — it is what makes the agent viable.**
SimpleFIN allows roughly **24 requests per day** and a **90-day maximum range** per
request. Storing `lastSyncedAt` per account means each sync pulls only what is new.
Without it, routine use would exhaust the daily budget.

## The egress rule, and where market data fits

The owner asked for market news and research. The concern was never "reading the
internet" — it is two specific things:

1. **Outbound channels that can carry data out.** This agent holds account balances
   in context. A free-text web search is model-composed text leaving the machine: a
   compromised model could encode balances in a query string. That is a data channel
   wearing a lookup's clothes.
2. **Untrusted content entering** a context that holds financial data.

The line that resolves it:

> **Ticker-keyed lookups against fixed hosts: allowed. Free-text web search: not on
> this agent.**

`stocks.quote` and `market.news` take a *symbol*, not a destination — the host is
fixed in the adapter, exactly like `google.search` fixes google.com. The model
chooses which company, never where to send anything.

For (2), the mitigation is structural: **with no egress, a successful injection has
no channel.** It could produce bad advice — a lesser harm, and one the user would
notice. Supporting evidence: Qwen passed 2/2 on injection-arriving-via-tool-result
in the multi-turn suite.

**Honest limitation:** "Bloomberg's report on a stock" is licensed content and is not
available through any free API. Reachable instead: quotes, company news headlines,
earnings dates and figures, analyst ratings — via Finnhub, which is already wired.

## Decisions taken (all 2026-08-11, owner)

**Budget lives in a note; spend derives from transactions.** Limits are declared by
the user, not inferred; spend-to-date is computed from SimpleFIN via category rules.

**SimpleFIN is the aggregator** — all four institutions verified supported:

| Institution | SimpleFIN listing |
|---|---|
| Bank of America | `Bank of America` |
| Marcus | `Marcus BY GOLDMAN SACHS` |
| E*TRADE | `E*Trade` |
| Capital One | `Capital One` |

**Plaid is rejected on permanence, not price.** Its Trial plan is free with real
production data for up to 10 Items, which would have fit — but Plaid states plainly
that it *does not offer a forever-free plan*, so it is a runway, not a floor.
SimpleFIN's ~$15/year buys permanence, and it is **read-only by design**, which is a
security property rather than a cost line.

**E*TRADE positions are in scope**, not just balances.

**The advisor may write:** decision notes, and budget limits under confirmation.

> **Scope note.** The month-start budget build means the agent authors the data it
> later reasons from — beyond "log decisions to notes" as originally chosen, and
> closer to "maintains the budget note". Accepted deliberately: it is the useful
> version. Mitigated by confirmation-gating every write and by the budget staying a
> human-readable note the user can inspect and correct at any time.

## New work this surfaces

**The report format has no chart block.** Block kinds today are `greeting`, `line`,
`metric`, `list`, `checklist`, `empty`, `count`, `proposal`, `scoreboard`,
`leaderboard`. `financial-analysis` needs a **series/chart block** — a genuine
addition to `report-document.schema.json` plus a renderer, not a configuration
change. It is the only part of this charter that changes a shared contract, and it
benefits every future agent that wants to plot something.

## Open items

1. **Income: declared or derived?** `income_expected_cents` is clearly declared
   during the budget conversation. Whether `income_actual_cents` is also declared or
   reconciled from deposit transactions is unsettled — reconciliation is nicer and
   needs a reliable way to recognise a paycheck.
2. **Category vocabulary.** Fixed list, or free-form per month? A fixed list makes
   month-over-month trends comparable, which `financial-analysis` depends on; free
   form is more flexible and makes trends mushy. Leaning fixed, user-editable.
3. **Transaction categorisation** — rules, or model-assigned with confirmation?
   Determines how much bookkeeping remains manual. `category_source` is in the schema
   so both can coexist and be told apart.
4. **Corpus sizing.** RAG vs wholesale inclusion, decided after measuring. The profile
   experiment showed a few highly-relevant facts beat volume; a large corpus may
   underperform a curated 2K-token summary.
5. **Backup isolation** — whether finances should be excludable from
   `BackupService` independently, which is the one argument for a separate database
   file.
