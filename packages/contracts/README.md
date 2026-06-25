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

## Planned Toolchain

The approved MVP stack uses JSON Schema 2020-12, Ajv for TypeScript-side validation, quicktype for generated Swift and TypeScript types, and strict Swift decoding against the same fixture suites. NIC-20 will add the concrete dependency versions, generation scripts, validation command, and drift checks after the first schemas exist.
