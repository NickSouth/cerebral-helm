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

Detailed dependency and ownership rules live in [repository boundaries](docs/architecture/repository-boundaries.md).

## Developer commands

NIC-12 now covers the runnable baseline plus the first safe operational helpers:

| Command | Purpose |
|---|---|
| `corepack pnpm run bootstrap` | Verify toolchains, validate repo config and simulation fixtures, install the JavaScript workspace, and prove the dashboard build succeeds. |
| `corepack pnpm run dashboard-dev` | Run the Pre-Mac dashboard development server from `apps/dashboard`. |
| `corepack pnpm run validate-config` | Validate repository config JSON and simulation fixtures without activating personal state. |
| `corepack pnpm run db-reset` | Reset the dedicated development database path under `.local/development/` without touching personal production roots. |
| `corepack pnpm run simulate` | Generate a preview-only simulation artifact and append a preview event to the development event log. |
| `corepack pnpm run events-tail` | Read the dedicated development event log when preview or runtime events exist. |
| `corepack pnpm run test` | Run `swift test`, dashboard unit tests, and the dashboard production build. |

If `just` is installed locally, the repository exposes matching shortcuts for the same command surface. Full setup notes live in [developer workspace](docs/operations/developer-workspace.md).
