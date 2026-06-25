# Fixtures

**Owner:** Quality engineering

**Purpose:** Deterministic, sanitized inputs shared by contract, core, dashboard, migration, and acceptance tests.

Fixtures must never contain personal production state or secrets.

`fixtures/simulations/` now holds preview-only command-surface inputs used by `simulate` and repository validation.
