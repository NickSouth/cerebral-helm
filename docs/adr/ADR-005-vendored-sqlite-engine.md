# ADR-005: Vendored SQLite via swift-toolchain-sqlite (GRDB deferred)

- Status: Accepted
- Date: 2026-06-28

## Context

PRE-DATA (NIC-42) introduces the operational SQLite store the MVP PRD locks
(`FR-OBS-01`): schema migrations, commands, command events, tool calls,
confirmations, note metadata, mode sessions, settings metadata, and update
history. `TECH-STACK.md` records SQLite as **locked storage** with **GRDB** as the
*recommended* wrapper ("Locked storage; recommended wrapper").

The pre-Mac foundation builds on a Windows development toolchain (Swift 6.3.2,
MSVC, OneDrive-synced working tree). That toolchain has repeatedly failed to build
C-backed dependencies: swift-crypto does not build, so SHA-256 is vendored in
`CerebralShared`. An engine probe confirmed the same class of failure for storage:
GRDB and SQLite.swift do **not** build/run on native Windows by default, while
`swiftlang/swift-toolchain-sqlite` — the SQLite amalgamation packaged as a single
C target — builds and runs. It is explicitly validated for Windows and ships the
Windows linker workaround (`swiftCore` linkage) in its own manifest.

`TECH-STACK.md` states: "An ADR may replace a recommended library. It may not
violate the command bus, policy, storage truth, confirmation, bridge, or update
boundaries locked by the MVP PRD." Choosing the engine is exactly that kind of
decision, and it must not change the locked fact that SQLite is the operational
store.

## Decision

Use `swiftlang/swift-toolchain-sqlite` (product `SwiftToolchainCSQLite`, the SQLite
amalgamation as a portable C target) as the SQLite engine for the pre-Mac
foundation. Pin it to the exact revision the engine probe validated
(`24de861…`, tag `1.0.10` + 1 commit) for reproducibility.

The package provides the raw SQLite C API and no Swift wrapper, by design. A thin,
hand-written Swift wrapper (`SQLiteDatabase`) over that C API lives in a new,
portable `CerebralStorage` package — the only package permitted to link the SQLite
engine. `CerebralCore` holds the storage **ports** and stays adapter-free;
`CerebralTools` does not depend on storage. Composition happens at the app layer.

GRDB remains the **post-Mac target** and is tracked as tech debt. Because all
storage access goes through `CerebralStorage` and the Core ports, GRDB can replace
the wrapper internals later without changing callers or the operational schema.

## Alternatives considered

### GRDB now (the recommended wrapper)

Rejected for the pre-Mac phase: it does not build on the Windows dev toolchain
(probe-confirmed). Adopting it now would block the entire PRE-DATA line on the one
environment the foundation is built in. Revisit on macOS, where GRDB is a clean fit
and brings migrations, FTS5, and observation.

### SQLite.swift

Rejected for the same reason (probe-confirmed Windows build failure), and it adds a
query-builder surface the deterministic MVP store does not need.

### Hand-vendoring the amalgamation (as with SHA-256)

Viable and matches the SHA-256 precedent, but `swift-toolchain-sqlite` is a
maintained, Swift-project-owned package that already vendors the same amalgamation
with the Windows linker workaround and a pinning story. Preferred over copying
`sqlite3.c` into the tree by hand.

## Consequences

### Positive

- The PRE-DATA storage line is unblocked on the existing Windows dev toolchain.
- The C dependency is isolated to one portable package (`CerebralStorage`); core
  stays adapter-free and portable (repository-boundary rule 1).
- Swapping to GRDB post-Mac is a wrapper-internal change behind stable ports, not
  an architectural rewrite, because schema and repositories sit above the wrapper.

### Negative

- We own a small amount of C-interop wrapper code (open/close, typed binds, row
  reads, transactions) instead of inheriting it from GRDB.
- The wrapper is intentionally minimal; richer features (observation, FTS helpers)
  arrive with GRDB later rather than now.

### Follow-on implications

- The eventual GRDB migration is a tracked tech-debt / post-Mac ticket.
- Foreign-key enforcement is a per-connection `PRAGMA`, so the wrapper sets it on
  open; migrations (PRE-DATA-4) own table/index/checksum concerns above it.
- `swift-argument-parser` stays pinned to `1.1.x` for the unrelated Windows plugin
  reason; the SQLite pin is independent.
