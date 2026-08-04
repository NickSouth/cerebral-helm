import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { resolveRepositoryRoot } from "./workspace-roots.mjs";

const repositoryRoot = resolveRepositoryRoot();
const contractsRoot = path.join(repositoryRoot, "packages", "contracts");
const schemasRoot = path.join(contractsRoot, "schemas", "tools");
const fixturesRoot = path.join(contractsRoot, "fixtures");

const mvpToolIds = new Set([
  "app.open",
  "project.open",
  "url.open",
  "hook.run",
  "note.capture",
  "note.search",
  "note.list",
  "note.read",
  "mode.apply",
  "system.status.read",
  "window.arrange",
  "apps.list",
  "network.speed.test",
  "apps.quitall",
  "app.quit",
  "calendar.createevent",
  "google.search",
  "youtube.search",
  "git.clone",
  "web.open",
  "spotify.control"
]);

const riskClasses = new Set([
  "read_only",
  "local_write",
  "external_write",
  "destructive",
  "shell",
  "financial",
  "purchase_or_booking"
]);

const toolResultStatuses = new Set(["success", "partial_success", "unavailable", "timeout", "denied", "failure", "cancelled"]);

const confirmationDisclosureFields = new Set([
  "actionSummary",
  "tool",
  "risk",
  "destination",
  "arguments",
  "dataLeavingDevice",
  "accountOrService",
  "reversibility",
  "policyReason",
  "choices",
  "expiresAt",
  "invalidation",
  "executionNotice"
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

test("tool schemas are present and parse as JSON Schema documents", () => {
  for (const schemaName of ["tool-descriptor.schema.json", "confirmation-disclosure.schema.json", "tool-result.schema.json"]) {
    const schema = readJson(path.join(schemasRoot, schemaName));

    assert.equal(schema.$schema, "https://json-schema.org/draft/2020-12/schema");
    assert.match(schema.$id, /^https:\/\/cerebralhelm\.local\/schemas\/tools\//);
  }
});

test("tool descriptor schema declares the exact MVP risk classes", () => {
  const schema = readJson(path.join(schemasRoot, "tool-descriptor.schema.json"));
  const observedRiskClasses = new Set(schema.$defs.riskClass.enum);

  assert.deepEqual(observedRiskClasses, riskClasses);
});

test("tool result schema declares stable result statuses", () => {
  const schema = readJson(path.join(schemasRoot, "tool-result.schema.json"));
  const observedStatuses = new Set(schema.properties.status.enum);

  assert.deepEqual(observedStatuses, toolResultStatuses);
});

test("valid descriptor fixtures cover every MVP tool with policy metadata", () => {
  const descriptorFiles = collectJsonFiles(path.join(fixturesRoot, "valid", "tools", "descriptors"));
  const observedToolIds = new Set();

  for (const filePath of descriptorFiles) {
    const descriptor = readJson(filePath);

    assert.ok(mvpToolIds.has(descriptor.id), `${filePath} has unexpected tool id ${descriptor.id}`);
    assert.match(descriptor.version, /^\d+\.\d+\.\d+$/);
    assert.ok(riskClasses.has(descriptor.risk), `${filePath} has unexpected risk ${descriptor.risk}`);
    assert.equal(typeof descriptor.confirmationPolicyKey, "string", `${filePath} must declare confirmationPolicyKey`);
    assert.equal(typeof descriptor.inputSchema?.schemaId, "string", `${filePath} must declare input schema reference`);
    assert.equal(typeof descriptor.outputSchema?.schemaId, "string", `${filePath} must declare output schema reference`);
    assert.ok(Array.isArray(descriptor.results) && descriptor.results.length > 0, `${filePath} must declare result statuses`);
    observedToolIds.add(descriptor.id);
  }

  assert.deepEqual(observedToolIds, mvpToolIds);
});

test("shell tools require shell risk and shell confirmation policy", () => {
  const descriptor = readJson(path.join(fixturesRoot, "valid", "tools", "descriptors", "hook.run.json"));

  assert.equal(descriptor.risk, "shell");
  assert.equal(descriptor.confirmationPolicyKey, "confirm_shell");
  assert.equal(descriptor.availability.preMac, false);
});

test("mode.apply declares runtime aggregation of planned action risk", () => {
  const descriptor = readJson(path.join(fixturesRoot, "valid", "tools", "descriptors", "mode.apply.json"));

  assert.equal(descriptor.risk, "local_write");
  assert.equal(descriptor.runtimeRiskPolicy, "highest_planned_action");
  assert.equal(descriptor.confirmationPolicyKey, "confirm_highest_planned_action");
});

test("invalid descriptor fixtures represent missing risk or policy metadata", () => {
  const invalidDescriptorsRoot = path.join(fixturesRoot, "invalid", "tools", "descriptors");
  const missingRisk = readJson(path.join(invalidDescriptorsRoot, "missing-risk.json"));
  const missingPolicy = readJson(path.join(invalidDescriptorsRoot, "missing-confirmation-policy.json"));

  assert.equal(Object.hasOwn(missingRisk, "risk"), false);
  assert.equal(Object.hasOwn(missingPolicy, "confirmationPolicyKey"), false);
});

test("confirmation disclosure schema covers PRD disclosure requirements", () => {
  const schema = readJson(path.join(schemasRoot, "confirmation-disclosure.schema.json"));
  const requiredFields = new Set(schema.required);

  for (const field of confirmationDisclosureFields) {
    assert.ok(requiredFields.has(field), `confirmation disclosure must require ${field}`);
  }
});

test("valid shell confirmation fixture is explicit and does not default to approval", () => {
  const disclosure = readJson(path.join(fixturesRoot, "valid", "tools", "confirmations", "shell-confirmation-disclosure.json"));

  assert.equal(disclosure.tool.id, "hook.run");
  assert.equal(disclosure.risk, "shell");
  assert.equal(disclosure.dataLeavingDevice, "none");
  assert.equal(disclosure.executionNotice, "Execution has not happened yet.");
  assert.notEqual(disclosure.choices.defaultFocusedChoice, "approve");
});
