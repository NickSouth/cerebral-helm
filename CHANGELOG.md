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

- PRE-CI quality-and-delivery foundation (NIC-66): GitHub Actions CI covering the
  portable Swift core (Linux + macOS), the dashboard (lint, typecheck, unit tests,
  production build), the contract/config/fixture/migration gates, secret scanning
  with a redaction-canary sweep, and documentation/compatibility checks.
- ESLint (flat config) and Prettier for the dashboard package.
- A migration upgrade-path test asserting recorded checksums stay canonical.

Config impact: none — this work adds CI and tooling only; no `config/*` defaults or
user-facing settings change.

Migration impact: none — no schema migrations were added.
