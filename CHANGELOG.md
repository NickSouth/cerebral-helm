# Changelog

All notable changes to CerebralHelm are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Every release entry must declare its configuration and migration impact on two
dedicated lines, so an operator can tell — without reading the diff — whether an
upgrade changes configuration defaults or runs a schema migration (NIC-70 AC-12):

- `Config impact:` — how the release affects `config/*` defaults or user overrides
  (`none` when it does not).
- `Migration impact:` — which schema migrations run on upgrade (`none` when it adds
  no migration).

## [Unreleased]

### Added

- Automatic pre-migration backups (NIC-95): opening the operational database now
  takes a verified snapshot into `<stateRoot>/backups/<timestamp>/` before applying
  any pending schema migration, and a failed or unverifiable backup blocks the
  migration. Wired at `operationalDatabase(_:)` — the single chokepoint the macOS
  app, the CLI, and every store helper share — so no surface can reach a schema
  write without passing it. A first run skips the snapshot: with no migrations
  applied there are no tables yet, so there is no user data to protect.
- Bounded backup retention (`BackupRetention`, NIC-95): the newest five snapshots
  are kept. Only directories carrying a readable `manifest.json` are deletion
  candidates, and the keep count is clamped to at least one, so pruning can never
  empty the directory or remove unmanaged content placed under `backups/`.
- `cerebral doctor` now reports the resolved environment and all seven durable
  roots, in both the healthy and the recovery outcome (NIC-91). A recovery
  diagnostic names a store but never a path, so without this there was no way to
  tell which environment's data had failed.
- PRE-CI quality-and-delivery foundation (NIC-66): GitHub Actions CI covering the
  portable Swift core (Linux + macOS), the dashboard (lint, typecheck, unit tests,
  production build), the contract/config/fixture/migration gates, secret scanning
  with a redaction-canary sweep, and documentation/compatibility checks.
- ESLint (flat config) and Prettier for the dashboard package.
- A migration upgrade-path test asserting recorded checksums stay canonical.

Config impact: none — this work adds CI and tooling only; no `config/*` defaults or
user-facing settings change.

Migration impact: none — no schema migrations were added.
