import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { resolveRepositoryRoot } from "./workspace-roots.mjs";

const repositoryRoot = resolveRepositoryRoot();
const contractsRoot = path.join(repositoryRoot, "packages", "contracts");
const schemasRoot = path.join(contractsRoot, "schemas", "bridge");
const fixturesRoot = path.join(contractsRoot, "fixtures", "valid", "bridge");
const invalidFixturesRoot = path.join(contractsRoot, "fixtures", "invalid", "bridge");

const expectedSchemaNames = new Set([
  "bootstrap-state.schema.json",
  "capability-state.schema.json",
  "event.schema.json",
  "handshake-request.schema.json",
  "handshake-response.schema.json",
  "operation-request.schema.json",
  "operation-response.schema.json",
  "settings-snapshot.schema.json"
]);

const bridgeOperations = new Set([
  "getBootstrapState",
  "submitCommand",
  "applyMode",
  "captureNote",
  "searchNotes",
  "decideConfirmation",
  "updateSettings",
  "subscribe",
  "getRecentActivity",
  "listApps",
  "updateQuickApps",
  "runSpeedTest",
  "getSettings",
  "addUrlReference",
  "listUrls",
  "listChromeProfiles",
  "addChromeProfileReference",
  "openLayout",
  "closeLayout",
  "toggleLayout",
  "pinLayoutWindow",
  "updateLayout",
  "captureLayout",
  "addLayoutTarget",
  "toggleModeCollapse",
  "closeAllWindows",
  "listWindows",
  "minimizeWindow",
  "surfaceWindow",
  "closeWindow"
]);

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function collectJsonFiles(directoryPath) {
  return fs
    .readdirSync(directoryPath, { withFileTypes: true })
    // statSync follows reparse points; a OneDrive Files-On-Demand placeholder
    // reports isFile()=false from readdir and would be silently skipped.
    .filter((entry) => entry.name.endsWith(".json") && fs.statSync(path.join(directoryPath, entry.name)).isFile())
    .map((entry) => path.join(directoryPath, entry.name));
}

test("bridge schemas are present and parse as JSON Schema documents", () => {
  const schemaFiles = collectJsonFiles(schemasRoot);
  const observedNames = new Set(schemaFiles.map((filePath) => path.basename(filePath)));

  assert.deepEqual(observedNames, expectedSchemaNames);

  for (const filePath of schemaFiles) {
    const schema = readJson(filePath);

    assert.equal(schema.$schema, "https://json-schema.org/draft/2020-12/schema");
    assert.match(schema.$id, /^https:\/\/cerebralhelm\.local\/schemas\/bridge\//);
  }
});

test("bridge operation schemas expose the shared CerebralBridge operation set", () => {
  const requestSchema = readJson(path.join(schemasRoot, "operation-request.schema.json"));
  const responseSchema = readJson(path.join(schemasRoot, "operation-response.schema.json"));

  assert.deepEqual(new Set(requestSchema.properties.operation.enum), bridgeOperations);
  assert.deepEqual(new Set(responseSchema.properties.operation.enum), bridgeOperations);
});

test("operation request fixtures cover every required bridge operation", () => {
  const operationFiles = collectJsonFiles(path.join(fixturesRoot, "operations")).filter((filePath) =>
    filePath.endsWith("-request.json")
  );
  const observedOperations = new Set(operationFiles.map((filePath) => readJson(filePath).operation));

  assert.deepEqual(observedOperations, bridgeOperations);
});

test("mock compatible handshake reports versions, capabilities, and no recovery", () => {
  const handshake = readJson(path.join(fixturesRoot, "handshake", "mock-compatible-response.json"));

  assert.equal(handshake.compatible, true);
  assert.equal(handshake.transport, "mock");
  assert.equal(handshake.bridgeVersion, "1.0.0");
  assert.equal(handshake.uiVersion, "0.1.0");
  assert.equal(handshake.coreVersion, "0.1.0");
  assert.equal(handshake.startupMode, "ready");
  assert.equal(handshake.recovery, null);
  assert.ok(handshake.capabilities.length >= 1);
});

test("degraded handshake makes unavailable capabilities explicit", () => {
  const handshake = readJson(path.join(fixturesRoot, "handshake", "degraded-capabilities-response.json"));
  const unavailableCapabilities = handshake.capabilities.filter((capability) => capability.available === false);

  assert.equal(handshake.compatible, true);
  assert.equal(handshake.startupMode, "degraded");
  assert.ok(unavailableCapabilities.length >= 1);
  assert.equal(handshake.degradedFeatures.length, unavailableCapabilities.length);

  for (const feature of handshake.degradedFeatures) {
    assert.match(feature.reason, /\S/);
    assert.ok(["unavailable", "offline", "error", "stale"].includes(feature.fallbackUiState));
  }
});

test("major-version mismatch fixture enters read-only recovery", () => {
  const handshake = readJson(path.join(fixturesRoot, "handshake", "major-version-mismatch-response.json"));

  assert.equal(handshake.compatible, false);
  assert.equal(handshake.bridgeVersion.startsWith("2."), true);
  assert.equal(handshake.startupMode, "recovery");
  assert.equal(handshake.recovery.reason, "major_version_mismatch");
  assert.equal(handshake.recovery.readOnly, true);
  assert.equal(handshake.recovery.diagnosticCode, "bridge_major_mismatch");
  assert.ok(handshake.degradedFeatures.some((feature) => feature.id === "bridge"));
});

test("invalid bridge fixtures represent rejected recovery and operation behavior", () => {
  const missingRecovery = readJson(path.join(invalidFixturesRoot, "handshake", "incompatible-without-recovery.json"));
  const unknownOperation = readJson(path.join(invalidFixturesRoot, "operations", "unknown-operation-request.json"));

  assert.equal(missingRecovery.compatible, false);
  assert.equal(missingRecovery.recovery, null);
  assert.equal(bridgeOperations.has(unknownOperation.operation), false);
});

test("bootstrap fixture preserves current dashboard bootstrap surface plus UI state", () => {
  const bootstrap = readJson(path.join(fixturesRoot, "bootstrap", "bootstrap-state.json"));

  for (const field of ["mode", "project", "summary", "commandsToday", "pendingConfirmations", "uiState", "heimlich", "expandedAgent"]) {
    assert.ok(Object.hasOwn(bootstrap, field), `bootstrap fixture must include ${field}`);
  }

  assert.equal(bootstrap.mode, "Executive");
  assert.equal(bootstrap.uiState, "ready");
});

test("bridge event fixtures cover command lifecycle and capability change events", () => {
  const eventTypes = new Set(collectJsonFiles(path.join(fixturesRoot, "events")).map((filePath) => readJson(filePath).type));

  assert.ok(eventTypes.has("command.lifecycle.transition"));
  assert.ok(eventTypes.has("bridge.capability.changed"));
});

test("read-surface operation getRecentActivity is declared and exercised (FR-OBS-04)", () => {
  const requestSchema = readJson(path.join(schemasRoot, "operation-request.schema.json"));
  const responseSchema = readJson(path.join(schemasRoot, "operation-response.schema.json"));

  assert.ok(requestSchema.properties.operation.enum.includes("getRecentActivity"), "request enum must include getRecentActivity");
  assert.ok(responseSchema.properties.operation.enum.includes("getRecentActivity"), "response enum must include getRecentActivity");

  const request = readJson(path.join(fixturesRoot, "operations", "get-recent-activity-request.json"));
  const response = readJson(path.join(fixturesRoot, "operations", "get-recent-activity-response.json"));

  assert.equal(request.operation, "getRecentActivity");
  assert.equal(response.operation, "getRecentActivity");
  assert.equal(response.status, "ok");

  // FR-OBS-04: recent commands, tool activity, confirmations, mode sessions, and structured errors.
  const activity = response.payload.recentActivity;
  for (const surface of ["commands", "toolCalls", "confirmations", "modeSessions", "errors"]) {
    assert.ok(
      Array.isArray(activity[surface]) && activity[surface].length >= 1,
      `recentActivity.${surface} must be a non-empty array`
    );
  }
});
