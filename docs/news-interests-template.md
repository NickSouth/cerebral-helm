# News Interests note

The News panel's relevance comes from a note in the knowledge vault, not from config
and not from code. This page explains the format and gives you a note to copy.

## Where it goes

Save it as **`news-interests.md`** — the documented home is `reference/news-interests.md`
under your knowledge root, but the note is found by **filename**, so a later triage pass
may move it to another folder without breaking anything. Renaming the file is the one
change that does break discovery.

If the note does not exist, the News panel behaves exactly as it did before it existed.

## The format

- A `##` heading names a **mode** — either its id (`executive`) or its label
  (`Executive`), matched case-insensitively.
- The bullets directly under that heading are the mode's search terms, in **priority
  order**: the note's order is what decides which terms survive when a query has to be
  trimmed.
- `## Any mode` (also `All modes` or `Global`) is the shared section, appended to every
  mode after its own terms.
- Every item is `- **term** — context`. The term is everything before the first dash;
  the context is yours, and is never matched against.
  Em dash (`—`), en dash (`–`) and a spaced hyphen (` - `) all work.
- A term in `"double quotes"` matches as an exact phrase. So does any term of more than
  one word — `open source` will not match an article that merely says "source".
- `**bold**`, `` `backticks` ``, `*italic*` and wikilinks are stripped from the term, so
  decorate it however reads best.
- Anything else in the note is free prose: a `###` sub-heading ends the mode section, a
  nested bullet is elaboration rather than a term, and a heading naming no mode is
  ignored.

## The note

Copy everything inside the block, stamping `created`/`updated` with the current time.

`cloudPolicy: allow` is deliberate and load-bearing: these terms are sent to NewsData.io
on every request, so the frontmatter should say so rather than claim a privacy the
feature does not have.

````markdown
---
schemaVersion: "1.0.0"
id: news-interests
title: News Interests
kind: reference
sensitivity: private
cloudPolicy: allow
status: active
created: "2026-08-19T00:00:00.000Z"
updated: "2026-08-19T00:00:00.000Z"
---

# News Interests

The search terms the News panel ranks headlines by, per mode. Most-important first —
order is priority. Context is for me, and for a future knowledge-base cleaning pass; it
is never matched against.

## Executive

- **artificial intelligence** — the industry I work in; funding, regulation, big-lab releases
- **"interest rates"** — affects the mortgage
- **New England** — where I live; local business and policy

## Developer

- **Swift** — my main language
- **"open source"** — the tooling I depend on
- **macOS** — the platform I ship on
- **"developer tools"** — editors, build systems, CI

## School

- **UMass** — my university
- **"computer science"** — my field
- **"financial aid"** — affects me directly

## Entertainment

- **Dune** — see the interests note; Part Three lands December 2026
- **Patriots** — NFL
- **"One Piece"** — quoted, or it matches every article about a piece of something
- **rugby** — All Blacks especially

## Any mode

- **New Zealand** — home
````

## See also

- [config/news/profiles.json](../config/news/profiles.json) — the per-mode category and
  RSS-feed mapping this note refines.
