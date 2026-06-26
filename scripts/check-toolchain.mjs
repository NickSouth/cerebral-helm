import { assertBinaryVersion, assertNodeVersion } from "./helpers.mjs";

const requireSwift = process.argv.includes("--require-swift");

const nodeVersion = assertNodeVersion("v22.0.0");
const corepackVersion = assertBinaryVersion("corepack", ["--version"], "0.30.0");
const pnpmVersion = assertBinaryVersion("corepack", ["pnpm", "--version"], "11.0.0");

console.log(`Node ${nodeVersion}`);
console.log(`corepack ${corepackVersion}`);
console.log(`pnpm ${pnpmVersion}`);

if (requireSwift) {
  const swiftVersionOutput = assertBinaryVersion("swift", ["--version"], "6.0.0");
  console.log(`swift ${swiftVersionOutput}`);
}
