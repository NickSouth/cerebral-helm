import { runCommand } from "./helpers.mjs";

runCommand("node", ["./scripts/check-toolchain.mjs", "--require-swift"]);
runCommand("swift", ["test"]);
runCommand("corepack", ["pnpm", "--dir", "apps/dashboard", "test", "--run"]);
runCommand("corepack", ["pnpm", "--dir", "apps/dashboard", "build"]);
