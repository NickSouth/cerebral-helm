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
| `just bootstrap` or `corepack pnpm run bootstrap` | Verify toolchains, install workspace dependencies, and prove the dashboard build succeeds on a fresh checkout. |
| `just dashboard-dev` or `corepack pnpm run dashboard-dev` | Start the Vite development server for `apps/dashboard` on `127.0.0.1`. |
| `just test` or `corepack pnpm run test` | Run `swift test`, dashboard unit tests, and the dashboard production build. |

## Scope

NIC-12 increment 1 standardizes the runnable baseline only:

- workspace bootstrap;
- dashboard development server;
- repository test entry point;
- explicit dependency version checks.

Later NIC-12 increments will add `validate-config`, `db-reset`, `simulate`, and `events-tail` once those backing systems exist.
