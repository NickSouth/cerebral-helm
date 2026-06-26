import fs from "node:fs";
import path from "node:path";
import {
  ensureDirectory,
  resolveEventLogPath,
  resolvePaths,
  resolveSimulationOutputRoot
} from "./workspace-roots.mjs";

function fail(message) {
  throw new Error(message);
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

const fixtureId = process.argv[2] ?? "successful-developer-mode";
const { fixtureRoot } = resolvePaths();
const fixturePath = path.join(fixtureRoot, "simulations", `${fixtureId}.json`);

if (!fs.existsSync(fixturePath)) {
  fail(`Simulation fixture "${fixtureId}" does not exist at ${fixturePath}.`);
}

const fixture = readJson(fixturePath);
const outputRoot = resolveSimulationOutputRoot();
const outputPath = path.join(outputRoot, `${fixtureId}.preview.json`);
const eventLogPath = resolveEventLogPath();

ensureDirectory(outputRoot);
ensureDirectory(path.dirname(eventLogPath));

const previewDocument = {
  generatedAt: new Date().toISOString(),
  status: "preview-only",
  fixtureId,
  fixturePath,
  summary: fixture.summary,
  source: fixture.source,
  modeId: fixture.modeId,
  steps: fixture.steps
};

fs.writeFileSync(outputPath, `${JSON.stringify(previewDocument, null, 2)}\n`);
fs.appendFileSync(
  eventLogPath,
  `${JSON.stringify({
    timestamp: previewDocument.generatedAt,
    type: "simulation.preview",
    fixtureId,
    outputPath
  })}\n`
);

console.log(`Prepared preview-only simulation artifact for "${fixtureId}".`);
console.log(`Preview output: ${outputPath}`);
console.log(`Preview event log: ${eventLogPath}`);
console.log("Simulation runtime is not implemented yet; this command validates fixture shape and writes a preview artifact only.");
