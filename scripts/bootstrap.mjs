import { runCommand } from "./helpers.mjs";

runCommand("node", ["./scripts/check-toolchain.mjs"]);
runCommand("node", ["./scripts/validate-config.mjs"]);
runCommand("node", ["./scripts/validate-compatibility.mjs"]);
runCommand("corepack", ["pnpm", "install"]);
runCommand("corepack", ["pnpm", "--dir", "apps/dashboard", "build"]);
