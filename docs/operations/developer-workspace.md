# Developer Workspace

This repository now exposes the first NIC-12 command surface for the portable Pre-Mac foundation. The commands in this document are safe for local development roots and do not target personal production state.

## Toolchain

- Node `22.x` or newer
- `corepack`
- `pnpm` `11.x`, resolved through `corepack`
- Swift `6.0` or newer on `PATH`

Run `node ./scripts/check-toolchain.mjs` or `corepack pnpm run check-toolchain` to confirm the JavaScript workspace toolchain. Add `--require-swift` when validating the full repository test surface.

## Primary Commands

Use `just` if it is installed locally. The repository also exposes equivalent `pnpm` scripts so a missing `just` binary does not block bootstrap.

| Command | Purpose |
|---|---|
| `just bootstrap` or `corepack pnpm run bootstrap` | Verify toolchains, validate config and simulation fixtures, install workspace dependencies, and prove the dashboard build succeeds on a fresh checkout. |
| `just dashboard-dev` or `corepack pnpm run dashboard-dev` | Start the Vite development server for `apps/dashboard` on `127.0.0.1`. |
| `just validate-config` or `corepack pnpm run validate-config` | Validate repository defaults, mode, agent, tool, and simulation fixture JSON. |
| `just validate-compatibility` or `corepack pnpm run validate-compatibility` | Validate the compatibility manifest and its major/minor policy invariants. |
| `just db-reset` or `corepack pnpm run db-reset` | Reset the dedicated development database file path under `.local/development/database/` and remove any SQLite sidecar files. |
| `just simulate` or `corepack pnpm run simulate` | Produce a preview-only simulation artifact from `fixtures/simulations/` and append a preview event to `.local/development/events/events.ndjson`. |
| `just events-tail` or `corepack pnpm run events-tail` | Show the latest lines from the dedicated development event log if preview or runtime events exist. |
| `just test` or `corepack pnpm run test` | Run `swift test`, dashboard unit tests, and the dashboard production build. |

## Safety Rules

- All operational writes stay under `.local/development/` by default.
- `CEREBRAL_STATE_ROOT`, `CEREBRAL_DATABASE_PATH`, `CEREBRAL_EVENT_LOG_PATH`, and `CEREBRAL_SIMULATION_OUTPUT_ROOT` may override locations only inside the repository workspace.
- Paths containing production-looking segments are rejected.
- No command in this repository defaults to personal production state.

## Current Limitations

- `db-reset` prepares and clears the dedicated development SQLite path, but it does not apply schema yet because the operational storage layer is not implemented.
- `simulate` is preview-only in this increment. It validates fixture inputs and writes artifacts without invoking a command bus or native adapters.
- `events-tail` reads the dedicated development event log when it exists. Runtime event streaming will arrive with the event system implementation.
