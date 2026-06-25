import path from "node:path";
import { contractsRoot, generateContracts, invokedDirectly } from "./contracts-shared.mjs";

export async function main() {
  const outputRoot = process.argv.includes("--out-dir")
    ? path.resolve(process.argv[process.argv.indexOf("--out-dir") + 1])
    : contractsRoot;

  if (!outputRoot) {
    throw new Error("--out-dir requires a path.");
  }

  const summary = await generateContracts(outputRoot);

  console.log(`Generated TypeScript contracts: ${summary.generatedTypescriptPath}`);
  console.log(`Generated Swift contracts: ${summary.generatedSwiftPath}`);
}

if (invokedDirectly(import.meta.url)) {
  main();
}
