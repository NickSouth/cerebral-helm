import { runCommand } from "./helpers.mjs";

runCommand("node", ["./scripts/check-toolchain.mjs", "--require-swift"]);
runCommand("node", ["./scripts/validate-config.mjs"]);
runCommand("node", ["./scripts/validate-compatibility.mjs"]);
runCommand("node", ["--test", "./scripts/command-surface.test.mjs"]);
runCommand("node", ["--test", "./scripts/compatibility.test.mjs"]);
runCommand("node", ["--test", "./scripts/contracts-command.test.mjs"]);
runCommand("node", ["--test", "./scripts/contracts-config.test.mjs"]);
runCommand("node", ["--test", "./scripts/contracts-tool.test.mjs"]);
runCommand("swift", ["test"]);
runCommand("corepack", ["pnpm", "--dir", "apps/dashboard", "test", "--run"]);
runCommand("corepack", ["pnpm", "--dir", "apps/dashboard", "build"]);
