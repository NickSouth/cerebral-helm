import { spawnSync } from "node:child_process";
import { runCommand } from "./helpers.mjs";

runCommand("node", ["./scripts/check-toolchain.mjs", "--require-swift"]);
runCommand("node", ["./scripts/validate-config.mjs"]);
runCommand("node", ["./scripts/validate-compatibility.mjs"]);
runCommand("node", ["./scripts/validate-contracts.mjs"]);
runCommand("node", ["./scripts/check-contract-drift.mjs"]);
runCommand("node", ["./scripts/secret-canary-sweep.mjs"]);
runCommand("node", ["./scripts/validate-docs.mjs"]);
runCommand("node", ["--test", "./scripts/command-surface.test.mjs"]);
runCommand("node", ["--test", "./scripts/compatibility.test.mjs"]);
runCommand("node", ["--test", "./scripts/contracts-bridge.test.mjs"]);
runCommand("node", ["--test", "./scripts/contracts-command.test.mjs"]);
runCommand("node", ["--test", "./scripts/contracts-config.test.mjs"]);
runCommand("node", ["--test", "./scripts/config-token-resolution.test.mjs"]);
runCommand("node", ["--test", "./scripts/config-reference-resolution.test.mjs"]);
runCommand("node", ["--test", "./scripts/quick-action-registry.test.mjs"]);
runCommand("node", ["--test", "./scripts/contracts-tool.test.mjs"]);
runCommand("node", ["--test", "./scripts/contracts-report.test.mjs"]);
runCommand("node", ["--test", "./scripts/fixture-catalog.test.mjs"]);
// The eval SUITE stays opt-in (it needs ~45 GB of models), but its descriptor ->
// manifest projection is pure and gated here: a defect in it does not fail an eval
// run, it silently corrupts every number the run produces.
runCommand("node", ["--test", "./scripts/evals-catalog.test.mjs"]);
runCommand("node", ["--test", "./scripts/evals-runtime.test.mjs"]);
runCommand("node", ["--test", "./scripts/validate-docs.test.mjs"]);
runCommand("swift", ["test"]);
runCommand("corepack", ["pnpm", "--dir", "apps/dashboard", "test", "--run"]);
runCommand("corepack", ["pnpm", "--dir", "apps/dashboard", "build"]);

// Visual-regression + accessibility guardrail. Skipped gracefully when the
// Playwright browsers are not installed (e.g. a cold CI or a fresh checkout) so a
// missing optional binary never hard-fails the whole suite.
const corepackBinary = process.platform === "win32" ? "corepack.cmd" : "corepack";
const browsersInstalled = spawnSync(
  corepackBinary,
  ["pnpm", "--dir", "apps/dashboard", "visual:available"],
  { stdio: "ignore", shell: process.platform === "win32" }
);

if (browsersInstalled.status === 0) {
  runCommand("corepack", ["pnpm", "--dir", "apps/dashboard", "test:visual"]);
} else {
  console.log(
    "Skipping dashboard visual regression: Playwright browsers not installed " +
      "(run: corepack pnpm --dir apps/dashboard exec playwright install chromium webkit)."
  );
}
