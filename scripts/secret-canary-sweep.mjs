import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { resolveRepositoryRoot } from "./workspace-roots.mjs";

// Secret-canary sweep (NIC-69 / FR-OBS-03, AC-7). Proves the redaction tests' fake
// secret markers never leak into shipped artifacts, generated output, or the built
// dashboard bundle. A single match fails the pipeline. This is the output-side
// complement to the Swift redaction tests, which prove the markers get redacted at
// the source; here we confirm they never surface in anything we ship.
//
// The sweep deliberately does NOT scan the Swift tests or this registry, where the
// canaries legitimately live — only the artifact/output directories declared in the
// registry's sweepPaths.

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const repositoryRoot = resolveRepositoryRoot();

// Built/asset files that are not text we author; searching them for a marker is
// noise (and binary reads can be large). The generated/fixture content we care about
// is all text.
const BINARY_EXTENSIONS = new Set([
  ".png", ".jpg", ".jpeg", ".gif", ".webp", ".ico", ".svg",
  ".woff", ".woff2", ".ttf", ".otf", ".eot",
  ".pdf", ".zip", ".gz", ".mp4", ".mov", ".wasm"
]);

function readRegistry() {
  const registryPath = path.join(scriptDirectory, "canary-registry.json");
  const registry = JSON.parse(fs.readFileSync(registryPath, "utf8"));

  if (typeof registry.marker !== "string" || registry.marker.length === 0) {
    throw new Error("canary-registry.json: marker must be a non-empty string.");
  }
  if (!Array.isArray(registry.sweepPaths) || registry.sweepPaths.length === 0) {
    throw new Error("canary-registry.json: sweepPaths must be a non-empty array.");
  }
  const knownCanaries = Array.isArray(registry.knownCanaries) ? registry.knownCanaries : [];
  return { marker: registry.marker, knownCanaries, sweepPaths: registry.sweepPaths };
}

function* walkFiles(directoryPath) {
  for (const entry of fs.readdirSync(directoryPath, { withFileTypes: true })) {
    const entryPath = path.join(directoryPath, entry.name);
    // statSync follows reparse points so a OneDrive Files-On-Demand placeholder is
    // still classified correctly rather than silently skipped.
    const stats = fs.statSync(entryPath);
    if (stats.isDirectory()) {
      yield* walkFiles(entryPath);
    } else if (stats.isFile() && !BINARY_EXTENSIONS.has(path.extname(entry.name).toLowerCase())) {
      yield entryPath;
    }
  }
}

function findMatches(content, marker, knownCanaries) {
  const matches = new Set();
  if (content.includes(marker)) {
    // Report each distinct canary-shaped token so the failure names the leak.
    const tokenPattern = new RegExp(`${marker.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}[A-Za-z0-9._-]*`, "g");
    for (const token of content.match(tokenPattern) ?? [marker]) {
      matches.add(token);
    }
  }
  for (const canary of knownCanaries) {
    if (content.includes(canary)) {
      matches.add(canary);
    }
  }
  return [...matches];
}

export function sweepCanaries() {
  const { marker, knownCanaries, sweepPaths } = readRegistry();
  const findings = [];
  const scanned = { files: 0, paths: [], skipped: [] };

  for (const relativePath of sweepPaths) {
    const absolutePath = path.join(repositoryRoot, relativePath);
    if (!fs.existsSync(absolutePath)) {
      scanned.skipped.push(relativePath);
      continue;
    }
    scanned.paths.push(relativePath);

    for (const filePath of walkFiles(absolutePath)) {
      scanned.files += 1;
      const content = fs.readFileSync(filePath, "utf8");
      const matches = findMatches(content, marker, knownCanaries);
      if (matches.length > 0) {
        findings.push({ file: path.relative(repositoryRoot, filePath), matches });
      }
    }
  }

  return { findings, scanned };
}

export function main() {
  const { findings, scanned } = sweepCanaries();

  if (scanned.skipped.length > 0) {
    // Not silent: name what was not present so absent build output reads honestly.
    console.log(`Canary sweep skipped absent paths: ${scanned.skipped.join(", ")}.`);
  }

  if (findings.length > 0) {
    const lines = findings.map((f) => `- ${f.file}: ${f.matches.join(", ")}`);
    throw new Error(
      `Secret canary leak detected in ${findings.length} file(s):\n${lines.join("\n")}\n` +
        "A redaction canary must never appear in a shipped artifact or build output."
    );
  }

  console.log(
    `Canary sweep clean: scanned ${scanned.files} files across ${scanned.paths.length} path(s); no canaries leaked.`
  );
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main();
}
