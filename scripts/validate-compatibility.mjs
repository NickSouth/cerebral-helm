import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { resolveRepositoryRoot } from "./workspace-roots.mjs";

function fail(message) {
  throw new Error(message);
}

function readJson(targetPath) {
  return JSON.parse(fs.readFileSync(targetPath, "utf8"));
}

function parseSemver(value, label) {
  const match = value.match(/^(\d+)\.(\d+)\.(\d+)$/);

  if (!match) {
    fail(`${label} must be semantic version x.y.z. Received "${value}".`);
  }

  return {
    major: Number(match[1]),
    minor: Number(match[2]),
    patch: Number(match[3])
  };
}

function validateContractEntry(name, entry, errors) {
  const parsed = parseSemver(entry.currentVersion, `contracts.${name}.currentVersion`);

  if (entry.compatibleMajor !== parsed.major) {
    errors.push(`contracts.${name}.compatibleMajor must match currentVersion major ${parsed.major}.`);
  }

  if (entry.compatibleMinorFloor > parsed.minor) {
    errors.push(`contracts.${name}.compatibleMinorFloor must be less than or equal to currentVersion minor ${parsed.minor}.`);
  }

  if (entry.majorMismatchOutcome !== "block_and_recover") {
    errors.push(`contracts.${name}.majorMismatchOutcome must be block_and_recover.`);
  }

  if (entry.minorMismatchOutcome !== "allow_with_capability_gating") {
    errors.push(`contracts.${name}.minorMismatchOutcome must be allow_with_capability_gating.`);
  }
}

function validateProviderEntry(entry, errors) {
  if (entry.requiredForMvp && entry.protocolVersion === null) {
    errors.push(`providers.entries.${entry.id} must declare protocolVersion when requiredForMvp is true.`);
  }
}

export function validateCompatibilityManifest() {
  const repositoryRoot = resolveRepositoryRoot();
  const manifestPath = path.join(repositoryRoot, "docs", "compatibility", "compatibility-manifest.json");
  const manifest = readJson(manifestPath);
  const errors = [];

  parseSemver(manifest.manifestSchemaVersion, "manifestSchemaVersion");
  parseSemver(manifest.manifestVersion, "manifestVersion");
  parseSemver(manifest.application.currentVersion, "application.currentVersion");

  for (const [name, entry] of Object.entries(manifest.contracts)) {
    validateContractEntry(name, entry, errors);
  }

  for (const entry of manifest.providers.entries) {
    validateProviderEntry(entry, errors);
  }

  if (manifest.providers.providersAreRuntimeVariables !== true) {
    errors.push("providers.providersAreRuntimeVariables must remain true in the Pre-Mac manifest.");
  }

  if (manifest.updatePolicy.majorMismatchBehavior !== "block_and_recover") {
    errors.push("updatePolicy.majorMismatchBehavior must remain block_and_recover.");
  }

  if (manifest.updatePolicy.minorMismatchBehavior !== "allow_with_capability_gating") {
    errors.push("updatePolicy.minorMismatchBehavior must remain allow_with_capability_gating.");
  }

  if (manifest.updatePolicy.patchMismatchBehavior !== "allow") {
    errors.push("updatePolicy.patchMismatchBehavior must remain allow.");
  }

  if (errors.length > 0) {
    fail(`Compatibility validation failed:\n- ${errors.join("\n- ")}`);
  }

  return {
    manifestPath,
    contractCount: Object.keys(manifest.contracts).length,
    providerCount: manifest.providers.entries.length,
    currentVersion: manifest.application.currentVersion
  };
}

const invokedPath = process.argv[1] ? path.resolve(process.argv[1]) : null;
const localPath = path.resolve(fileURLToPath(import.meta.url));

if (invokedPath === localPath) {
  const summary = validateCompatibilityManifest();
  console.log(
    `Validated compatibility manifest ${summary.currentVersion} with ${summary.contractCount} contracts and ${summary.providerCount} provider entries.`
  );
  console.log(`Manifest file: ${summary.manifestPath}`);
}
