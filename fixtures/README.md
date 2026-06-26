# Fixtures

**Owner:** Quality engineering

**Purpose:** Deterministic, sanitized inputs shared by contract, core, dashboard, migration, and acceptance tests.

Fixtures must never contain personal production state or secrets.

Current fixture groups:

- `fixtures/catalog/`: Canonical named product-state fixtures shared by core tests, dashboard mock/story data, simulations, and acceptance flows.
- `fixtures/simulations/`: Preview-only command-surface inputs used by `simulate` and repository validation.
