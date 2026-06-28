# Knowledge template

**Owner:** Knowledge

**Purpose:** Seed the user-owned Markdown hierarchy without making repository
content authoritative over user data. Updates may add optional templates but must
never overwrite a user's knowledge tree.

Markdown files are the human-readable **source of truth** for notes and project
context (`FR-KNW-01`). They remain readable and editable outside CerebralHelm.
SQLite holds only *derived* note metadata and a rebuildable search index — never
the note body.

## Hierarchy (FR-KNW-03)

The default tree separates durable concerns so notes have one obvious home:

| Folder | Holds |
|---|---|
| [`profile/`](profile/) | Durable personal identity — who the user is (name, education, relationships, preferences). |
| [`inbox/`](inbox/) | Unsorted quick capture, awaiting triage. Transient. |
| [`daily/`](daily/) | Day notes / journal entries, one per date. |
| [`projects/`](projects/) | Goal-bound efforts with an end state. |
| [`areas/`](areas/) | Ongoing responsibilities with no end state. |
| [`reference/`](reference/) | Durable reference material. |
| [`archive/`](archive/) | Completed or inactive notes moved out of the active folders. |

`profile/` holds stable facts about the user — distinct from a *project* (no goal),
an *area* (identity, not a responsibility), or *reference* (about you, not external
material). It is the core context Heimlich draws on, and its notes default to at
least `sensitivity: sensitive` + `cloudPolicy: deny`. A *structured* user model is
North-Star/future; today the profile is durable notes with a first-class home.

**Modes reference these durable folders; they do not duplicate notes (AC-43.2).**
A mode's `projectHints` point at projects/areas by id — the note lives once, in
its folder, and every mode that cares about it references the same file. Knowledge
is never copied per mode.

## Naming rules

- File names are derived from a stable, lowercase, URL/file-safe **id**
  (`^[a-z0-9][a-z0-9-]*$`) plus the `.md` extension, so a note is safe on disk and
  linkable.
- The human `title` lives in frontmatter and may contain any text.
- `kind` and `project` are lowercase slugs (`^[a-z][a-z0-9-]*$`).

## Note frontmatter and safe defaults (FR-KNW-05)

Every note carries a system-managed YAML frontmatter block — the contract is
[`note-metadata.schema.json`](../packages/contracts/schemas/knowledge/note-metadata.schema.json).
Required: `schemaVersion`, `id`, `title`, `kind`, `sensitivity`, `cloudPolicy`,
`status`, `created`, `updated`. Optional: `project`, `reviewAfter`. User-added
frontmatter keys are preserved by the note codec and sit outside this contract.

When optional metadata is absent it degrades to **safe defaults**, applied by the
capture path (PRE-DATA-2):

| Field | Safe default | Why |
|---|---|---|
| `sensitivity` | `private` | Treat unmarked notes as personal, not public. |
| `cloudPolicy` | `deny` | Never auto-allow cloud transmission — defaults to deny or ask, **never `allow`** (AC-43.3). |
| `status` | `active` | A captured note is live unless marked draft/archived. |
| `created` / `updated` | capture time | Stamped when the note is written. |

`reviewAfter` is the optional freshness boundary: past that instant a note is due
for review (search surfaces this as freshness, PRE-DATA-3).
