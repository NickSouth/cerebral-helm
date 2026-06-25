import fs from "node:fs";
import path from "node:path";
import {
  generateContracts,
  invokedDirectly,
  makeTemporaryContractOutputRoot,
  swiftOutputPath,
  typescriptOutputPath
} from "./contracts-shared.mjs";

function assertMatches(actualPath, expectedPath, label, errors) {
  if (!fs.existsSync(actualPath)) {
    errors.push(`${label} is missing at ${actualPath}. Run node ./scripts/generate-contracts.mjs.`);
    return;
  }

  const actual = fs.readFileSync(actualPath, "utf8");
  const expected = fs.readFileSync(expectedPath, "utf8");

  if (actual !== expected) {
    errors.push(`${label} is stale. Run node ./scripts/generate-contracts.mjs.`);
  }
}

export async function checkContractDrift() {
  const temporaryRoot = makeTemporaryContractOutputRoot();
  const generated = await generateContracts(temporaryRoot);
  const errors = [];

  assertMatches(typescriptOutputPath, generated.generatedTypescriptPath, "Generated TypeScript contracts", errors);
  assertMatches(swiftOutputPath, generated.generatedSwiftPath, "Generated Swift contracts", errors);

  fs.rmSync(temporaryRoot, { recursive: true, force: true });

  if (errors.length > 0) {
    throw new Error(`Contract drift check failed:\n- ${errors.join("\n- ")}`);
  }

  return {
    typescriptOutputPath,
    swiftOutputPath
  };
}

export async function main() {
  const summary = await checkContractDrift();

  console.log(`Generated TypeScript contracts are current: ${path.relative(process.cwd(), summary.typescriptOutputPath)}`);
  console.log(`Generated Swift contracts are current: ${path.relative(process.cwd(), summary.swiftOutputPath)}`);
}

if (invokedDirectly(import.meta.url)) {
  main();
}
