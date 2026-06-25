import fs from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { resolvePaths } from "./workspace-roots.mjs";

function fail(message) {
  throw new Error(message);
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function assert(condition, message, errors) {
  if (!condition) {
    errors.push(message);
  }
}

function validateDefaults(document, relativePath, errors) {
  assert(typeof document.schemaVersion === "string", `${relativePath}: schemaVersion must be a string.`, errors);
  assert(typeof document.defaultModeId === "string", `${relativePath}: defaultModeId must be a string.`, errors);
  assert(Array.isArray(document.enabledAgentIds), `${relativePath}: enabledAgentIds must be an array.`, errors);
  assert(Array.isArray(document.enabledToolIds), `${relativePath}: enabledToolIds must be an array.`, errors);
}

function validateMode(document, relativePath, errors) {
  assert(typeof document.id === "string", `${relativePath}: id must be a string.`, errors);
  assert(typeof document.label === "string", `${relativePath}: label must be a string.`, errors);
  assert(typeof document.accent === "string", `${relativePath}: accent must be a string.`, errors);
  assert(Array.isArray(document.quickApps), `${relativePath}: quickApps must be an array.`, errors);
  assert(
    Array.isArray(document.quickApps) && document.quickApps.length >= 1 && document.quickApps.length <= 5,
    `${relativePath}: quickApps must contain between 1 and 5 entries.`,
    errors
  );
  assert(Array.isArray(document.agentIds), `${relativePath}: agentIds must be an array.`, errors);
  assert(Array.isArray(document.shortcuts), `${relativePath}: shortcuts must be an array.`, errors);
}

function validateAgent(document, relativePath, errors) {
  assert(typeof document.id === "string", `${relativePath}: id must be a string.`, errors);
  assert(typeof document.label === "string", `${relativePath}: label must be a string.`, errors);
  assert(typeof document.status === "string", `${relativePath}: status must be a string.`, errors);
  assert(typeof document.summary === "string", `${relativePath}: summary must be a string.`, errors);
}

function validateTool(document, relativePath, errors) {
  assert(typeof document.id === "string", `${relativePath}: id must be a string.`, errors);
  assert(typeof document.risk === "string", `${relativePath}: risk must be a string.`, errors);
  assert(typeof document.timeoutMs === "number", `${relativePath}: timeoutMs must be a number.`, errors);
  assert(typeof document.availableInPreMac === "boolean", `${relativePath}: availableInPreMac must be a boolean.`, errors);
}

function validateSimulation(document, relativePath, errors) {
  assert(typeof document.id === "string", `${relativePath}: id must be a string.`, errors);
  assert(typeof document.source === "string", `${relativePath}: source must be a string.`, errors);
  assert(typeof document.modeId === "string", `${relativePath}: modeId must be a string.`, errors);
  assert(typeof document.summary === "string", `${relativePath}: summary must be a string.`, errors);
  assert(Array.isArray(document.steps), `${relativePath}: steps must be an array.`, errors);
  assert(
    Array.isArray(document.steps) && document.steps.every((step) => typeof step === "string"),
    `${relativePath}: every step must be a string.`,
    errors
  );
}

function collectJsonFiles(directoryPath) {
  return fs
    .readdirSync(directoryPath, { withFileTypes: true })
    .filter((entry) => entry.isFile() && entry.name.endsWith(".json"))
    .map((entry) => path.join(directoryPath, entry.name));
}

export function validateRepositoryConfig() {
  const { configRoot, fixtureRoot } = resolvePaths();
  const errors = [];

  const defaultsPath = path.join(configRoot, "defaults", "app.json");
  const modeFiles = collectJsonFiles(path.join(configRoot, "modes"));
  const agentFiles = collectJsonFiles(path.join(configRoot, "agents"));
  const toolFiles = collectJsonFiles(path.join(configRoot, "tools"));
  const simulationFiles = collectJsonFiles(path.join(fixtureRoot, "simulations"));

  validateDefaults(readJson(defaultsPath), path.relative(configRoot, defaultsPath), errors);

  for (const filePath of modeFiles) {
    validateMode(readJson(filePath), path.relative(configRoot, filePath), errors);
  }

  for (const filePath of agentFiles) {
    validateAgent(readJson(filePath), path.relative(configRoot, filePath), errors);
  }

  for (const filePath of toolFiles) {
    validateTool(readJson(filePath), path.relative(configRoot, filePath), errors);
  }

  for (const filePath of simulationFiles) {
    validateSimulation(readJson(filePath), path.relative(fixtureRoot, filePath), errors);
  }

  const modeIds = new Set(modeFiles.map((filePath) => readJson(filePath).id));
  const agentIds = new Set(agentFiles.map((filePath) => readJson(filePath).id));
  const toolIds = new Set(toolFiles.map((filePath) => readJson(filePath).id));
  const defaults = readJson(defaultsPath);

  assert(modeIds.has(defaults.defaultModeId), `defaults/app.json: defaultModeId "${defaults.defaultModeId}" must reference a mode file.`, errors);

  for (const agentId of defaults.enabledAgentIds ?? []) {
    assert(agentIds.has(agentId), `defaults/app.json: enabledAgentId "${agentId}" must reference an agent file.`, errors);
  }

  for (const toolId of defaults.enabledToolIds ?? []) {
    assert(toolIds.has(toolId), `defaults/app.json: enabledToolId "${toolId}" must reference a tool file.`, errors);
  }

  for (const filePath of modeFiles) {
    const document = readJson(filePath);

    for (const agentId of document.agentIds ?? []) {
      assert(agentIds.has(agentId), `${path.relative(configRoot, filePath)}: agentId "${agentId}" must reference an agent file.`, errors);
    }
  }

  if (errors.length > 0) {
    fail(`Configuration validation failed:\n- ${errors.join("\n- ")}`);
  }

  return {
    defaultsPath,
    modeCount: modeFiles.length,
    agentCount: agentFiles.length,
    toolCount: toolFiles.length,
    simulationCount: simulationFiles.length
  };
}

export function main() {
  const summary = validateRepositoryConfig();

  console.log(
    `Validated ${summary.modeCount} modes, ${summary.agentCount} agents, ${summary.toolCount} tools, and ${summary.simulationCount} simulations.`
  );
  console.log(`Defaults file: ${summary.defaultsPath}`);
}

if (process.argv[1] && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url) {
  main();
}
