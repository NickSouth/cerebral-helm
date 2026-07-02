# Continuous Integration

**Owner:** Operations

**Purpose:** Describe the pull-request CI that keeps the portable foundation
continuously verifiable before a release pipeline exists (PRD G-08, NFR-01). The
workflow lives at [`.github/workflows/ci.yml`](../../.github/workflows/ci.yml).

## Triggers

- Every pull request.
- Every push to `dev` and `prod`.

Superseded runs on the same ref are cancelled so the latest commit is the one that
gates.

## Jobs

Each surface is a separately named job. A red check names the package that owns the
failure, and the job names are the stable identifiers to mark **required** in the
branch-protection rule for `prod` (and `dev`, if protected).

| Job name | Runner | Owns | Steps |
|---|---|---|---|
| `dashboard` | `ubuntu-latest` | `apps/dashboard` | install (frozen lockfile) → lint → typecheck → unit tests → production build |
| `core-swift-linux` | `ubuntu-latest` (Swift container) | portable Swift core (`packages/*`, `apps/cli`) on non-Mac | `swift test` |
| `core-swift-macos` | `macos-15` | portable Swift core on Apple's toolchain | verify Swift ≥ 6.0 → `swift test` |

Later increments add named jobs to the same workflow: `contracts-config` (NIC-68),
`secrets` (NIC-69), and `docs` (NIC-70). Add each to the required set as it lands.

## Design notes

- **Lockfile drift (AC-2):** installs use `pnpm install --frozen-lockfile`, which
  fails when `pnpm-lock.yaml` is out of sync with any `package.json` regardless of
  the pnpm store cache state. The cache only stores downloaded packages, never the
  resolution, so a warm cache cannot mask drift.
- **Failure ownership (AC-3):** one job per surface plus named steps, so a failing
  check points at the owning package without reading logs.
- **Branch-protection readiness (AC-1):** job names are stable and documented here;
  they are the exact strings to select as required status checks.
- **Caches:** the pnpm store is keyed on `pnpm-lock.yaml` (via `setup-node`); the
  SwiftPM `.build` directory is keyed on `Package.resolved` + `Package.swift`.
- **Swift floor:** the Linux job pins the toolchain through the `swift:6.1` container
  image (bump the tag to raise the floor). The macOS job asserts `swift --version`
  is at least 6.0 before compiling so an old default toolchain fails loudly.
- **Local parity:** the dashboard steps mirror the scripts the local runner
  ([`scripts/test.mjs`](../../scripts/test.mjs)) already invokes; `swift test` is the
  same command. Playwright visual regression is intentionally **not** a CI job — its
  baselines are win32-only and browsers are not installed on these runners.

## macOS runner cost

macOS minutes are billed at a higher multiplier than Linux. The `.build` cache keeps
`core-swift-macos` incremental. If cost becomes a concern, the macOS job can be
narrowed to pushes/PRs targeting `prod` while Linux keeps running on every change;
that is a tuning knob, not a current constraint.
