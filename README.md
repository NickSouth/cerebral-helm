# CerebralHelm, driven by Heimlich

CerebralHelm is a local-first personal command layer for macOS. Heimlich is its assistant and interaction identity. The current work is the portable Pre-Mac foundation described by the [MVP PRD](.agent/spec/MVP-PRD.md).

## Repository boundaries

| Area | Owner | Purpose |
|---|---|---|
| `.agent/` | Product and architecture | Canonical implementation specifications and agent guidance |
| `Tests/` | Quality engineering | Cross-package repository boundary and contract tests |
| `apps/` | Application surfaces | Dashboard and platform application entry points |
| `packages/` | Portable core | Swift domain modules and language-neutral contracts |
| `config/` | Configuration | Versioned defaults for modes, agents, and tools |
| `database/` | Storage | Ordered operational database migrations |
| `fixtures/` | Quality engineering | Deterministic, non-personal test inputs |
| `knowledge-template/` | Knowledge | Seed hierarchy for user-owned Markdown knowledge |
| `docs/` | Architecture and operations | ADRs, architecture, compatibility, and operational guidance |
| `scripts/` | Developer experience | Portable automation used by documented commands |
| `wiki/` | Product | Long-lived product direction beyond the MVP boundary |

Detailed dependency and ownership rules live in [repository boundaries](docs/architecture/repository-boundaries.md). Developer bootstrap and command documentation are intentionally deferred to NIC-12.
