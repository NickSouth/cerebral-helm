# Contracts

**Owner:** Contracts

**Purpose:** Canonical JSON Schema documents, fixtures, and reproducibly generated Swift and TypeScript representations.

Contracts are language-neutral and versioned. Command, event, tool, bridge, configuration, and compatibility schemas will be added by their owning implementation issues.

## Ownership Rules

- JSON Schema files in `schemas/` are the source of truth.
- Files under `generated/` and `Sources/CerebralContracts/` are generated consumers and must not become the contract authority.
- Fixtures in `fixtures/` are canonical shared examples for contract tests, dashboard mocks, simulations, and future acceptance flows.
- Product code may import generated bindings, but it must not depend on `.agent/`, `docs/`, or `wiki/` at runtime.

## Layout

| Path | Purpose |
|---|---|
| `schemas/` | Versioned JSON Schema 2020-12 documents. |
| `fixtures/` | Valid and invalid examples with stable IDs and clocks. |
| `generated/typescript/` | Reproducibly generated TypeScript bindings. |
| `Sources/CerebralContracts/` | Reproducibly generated Swift `Codable` DTOs plus package boundary marker. |

## Toolchain

The approved MVP stack uses JSON Schema 2020-12, Ajv validation, quicktype-generated Swift and TypeScript types, and Swift decoding against the same fixture suites.

| Command | Purpose |
|---|---|
| `npm run generate-contracts` | Regenerate TypeScript and Swift bindings from JSON Schemas. |
| `npm run validate-contracts` | Compile every schema and validate all canonical valid/invalid fixtures plus checked-in config examples. |
| `npm run check-contract-drift` | Regenerate contracts in a temporary directory and fail if checked-in generated bindings are stale. |
| `npm test` | Runs validation, drift detection, focused contract tests, Swift tests, and dashboard checks. |
