import { runCommand } from "./helpers.mjs";

runCommand("node", ["./scripts/check-toolchain.mjs"]);
runCommand("corepack", ["pnpm", "--dir", "apps/dashboard", "dev", "--", "--host", "127.0.0.1"]);
