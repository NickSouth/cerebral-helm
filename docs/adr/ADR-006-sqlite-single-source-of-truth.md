# ADR-006: SQLite as the single source of truth for operational history (NDJSON/file adapters demoted)

- Status: Accepted
- Date: 2026-06-28

## Context

PRE-DATA increment 4b lands the SQLite operational repositories on the engine and
package established by [ADR-005](ADR-005-vendored-sqlite-engine.md)
(`swift-toolchain-sqlite` behind a `CerebralStorage` package, with the storage
**ports** in `CerebralCore`). `FR-OBS-01` locks SQLite as **the** operational store
(schema migrations, commands, command events, tool calls, confirmations, note
metadata, mode sessions, settings metadata, update history).

The pre-Mac foundation currently persists operational history **outside** SQLite,
through deliberate placeholders bound behind the Core ports:

- `EventLogWriter` → an NDJSON event log, read by `EventLogReader` / `CommandStatusReader`;
- `FileModeStateStore` → active mode/context as files;
- `NDJSONModeSessionLog` → an append-only mode-session log.

These were always explicit stand-ins meant to be swapped (NIC-33 ships durable
implementations behind ports with mock/stub bindings). 4b must resolve the open
question: when the SQLite repositories arrive, do they **replace** these stores
(single source of truth, read surfaces repointed) or run **alongside** them (SQLite
authoritative, NDJSON kept as a redundant pre-Mac dev log)? The answer determines
how much of `CommandStatusReader` / `EventLogReader` changes in this issue.

Two locked principles constrain the choice: durable state has a **single source of
truth** with no silent divergence, and user state is **never silently
reset/replaced/migrated**. Pre-Mac, the affected records live under
`.local/development` — development data, not personal production — so there is no
real user state to migrate at cutover.

## Decision

**SQLite is the single source of truth for operational history.** When the
`CerebralStorage` repositories land (PRE-DATA 4b), they **replace** the NDJSON event
log and the file mode-state/session adapters as the production stores, and the read
surfaces (`CommandStatusReader`, `EventLogReader`, and the mode-state/session reads)
are repointed to read from SQLite through the Core ports.

- **No dual authoritative stores.** The runtime writes operational records to SQLite
  only.
- **Demote, do not delete.** The NDJSON/file adapters remain available as
  test/fixture bindings behind the same Core ports (deterministic unit tests,
  fallback), but are not part of the production write or read path.
- **Inspectability via a read path, not a parallel write.** Human-readable logs are
  served by a read-only export/tail that renders NDJSON **from** SQLite.
- **Scope may split, the invariant may not.** If repointing the readers makes 4b too
  large, the reader migration may move to a thin follow-on increment — but the
  steady state is never two authoritative stores.

The cutover is performed pre-Mac, while the only affected data is development data,
so it is not a personal-state migration.

## Alternatives considered

### SQLite authoritative + NDJSON as a redundant pre-Mac dev log (run alongside)

Rejected as a steady state. Two stores holding the same operational history can
diverge after a crash, a partial write, or a bug, producing a "which is true?"
question about the one record that must be trustworthy — directly against the
single-source-of-truth principle — and it defers the reader migration into a window
where the two stores can disagree. The only acceptable residue of NDJSON is a
strictly **write-only, disposable** diagnostic sink that nothing reads back; even
that is write amplification for marginal benefit and is not adopted.

### Defer the reader repoint; SQLite writes but NDJSON stays the read source

Rejected: this is the alongside hazard in disguise. If readers trust NDJSON while
SQLite is nominally "authoritative," SQLite is not actually the source of truth.
Splitting the reader repoint into its own increment is fine; leaving readers pointed
at a different store than the source of truth is not.

### Keep file/NDJSON as production stores pre-Mac, adopt SQLite only on macOS

Rejected: it wastes the cheapest cutover window (no personal data exists pre-Mac) and
makes SQLite first become authoritative at the same moment real personal data
appears — the riskiest possible time. Cutting over now lets SQLite prove itself
against development data first.

## Consequences

### Positive

- One trustworthy operational history; no divergence to reconcile.
- The cutover carries no personal-state migration risk (development data only) and
  exercises SQLite before any real user data exists.
- Write path and read surfaces converge on the Core ports + `CerebralStorage`,
  matching the ADR-005 boundary.

### Negative

- 4b carries the reader repoint (`CommandStatusReader` / `EventLogReader` and the
  mode-state/session reads), a larger increment than a write-only change — mitigated
  by the optional split into a thin follow-on.
- The always-on plaintext NDJSON log stops being a default; recovered through the
  export/tail-from-SQLite read path.

### Follow-on implications

- The export/tail-from-SQLite read path is a small, named deliverable for dev
  inspectability.
- File/NDJSON adapters are retained as test bindings; a tidy follow-up may relocate
  them from `CerebralTools` into `CerebralStorage` so all storage adapters live
  together (per ADR-005's package boundary).
- `RepositoryBoundaryTests` should assert `CerebralStorage` is the **only** package
  linking the SQLite C target, reinforcing ADR-005 so the engine cannot leak into
  Core/Tools/Knowledge.
- Confirmation persistence (NIC-112) and the operational repositories (NIC-47) write
  to the same SQLite store under one migration identity (NIC-46), keeping FR-SAF-05
  durability and FR-OBS-01 coherent.
