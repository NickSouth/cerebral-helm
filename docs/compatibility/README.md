# Compatibility

**Owner:** Release and contracts

**Purpose:** Document app, bridge, config, database, platform, protocol, and provider version comparison.

Current compatibility sources:

- [compatibility-manifest.json](compatibility-manifest.json): repository-owned compatibility metadata for the current Pre-Mac release line
- [compatibility-manifest.schema.json](compatibility-manifest.schema.json): JSON Schema for manifest shape and required fields

## Version policy

- Major mismatches are incompatible and must block startup or update continuation with recovery guidance.
- Minor mismatches may continue only with explicit capability gating and degraded-feature reporting.
- Patch mismatches are compatible unless a stricter contract-specific rule is added later.
- Provider and OS values are compatibility metadata, not product invariants scattered across logic.
- Future providers remain runtime configuration concerns unless a provider becomes an MVP requirement.

## Current Pre-Mac stance

- Bridge, config, database, command envelope, command events, and tool descriptor contracts are all tracked as versioned compatibility entries.
- Non-Mac Pre-Mac development is supported with mock bridge and fixture-safe roots.
- Native macOS minimum version remains intentionally unset until first-Mac validation in NIC-15.

Run `node ./scripts/validate-compatibility.mjs` or `corepack pnpm run validate-compatibility` to validate the current manifest.
