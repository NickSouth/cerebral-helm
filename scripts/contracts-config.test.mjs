import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { resolveRepositoryRoot } from "./workspace-roots.mjs";

const repositoryRoot = resolveRepositoryRoot();
const contractsRoot = path.join(repositoryRoot, "packages", "contracts");
const schemasRoot = path.join(contractsRoot, "schemas", "config");
const fixturesRoot = path.join(contractsRoot, "fixtures");
const configRoot = path.join(repositoryRoot, "config");

const expectedModeIds = new Set(["executive", "developer", "school", "entertainment"]);
const expectedAgentIds = new Set(["research-analyst", "financial-advisor", "project-manager", "system-janitor"]);
const expectedSchemaNames = new Set([
  "agent.schema.json",
  "app-defaults.schema.json",
  "config-validation-error.schema.json",
  "mode.schema.json",
  "mode-override.schema.json",
  "model-composer.schema.json",
  "model-profiles.schema.json",
  "settings-patch.schema.json"
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

function schemaRequiredFields(schemaName) {
  return new Set(readJson(path.join(schemasRoot, schemaName)).required);
}

function resolveLocalRef(schema, value) {
  if (!value?.$ref?.startsWith("#/$defs/")) {
    return value;
  }

  return schema.$defs[value.$ref.slice("#/$defs/".length)];
}

function assertOnlyKnownTopLevelKeys(document, schemaName, filePath) {
  const schema = readJson(path.join(schemasRoot, schemaName));
  const allowedKeys = new Set(Object.keys(schema.properties));

  for (const key of Object.keys(document)) {
    assert.ok(allowedKeys.has(key), `${filePath} uses unknown top-level key ${key}`);
  }
}

test("config schemas are present and parse as JSON Schema documents", () => {
  const schemaFiles = collectJsonFiles(schemasRoot);
  const observedNames = new Set(schemaFiles.map((filePath) => path.basename(filePath)));

  assert.deepEqual(observedNames, expectedSchemaNames);

  for (const filePath of schemaFiles) {
    const schema = readJson(filePath);

    assert.equal(schema.$schema, "https://json-schema.org/draft/2020-12/schema");
    assert.match(schema.$id, /^https:\/\/cerebralhelm\.local\/schemas\/config\//);
  }
});

test("current defaults reference the four configured agents and a configured mode", () => {
  const defaults = readJson(path.join(configRoot, "defaults", "app.json"));
  const requiredFields = schemaRequiredFields("app-defaults.schema.json");

  for (const field of requiredFields) {
    assert.ok(Object.hasOwn(defaults, field), `defaults/app.json must contain ${field}`);
  }

  assert.ok(expectedModeIds.has(defaults.defaultModeId));
  assert.deepEqual(new Set(defaults.enabledAgentIds), expectedAgentIds);
});

test("current mode configs fit the mode schema surface", () => {
  const modeFiles = collectJsonFiles(path.join(configRoot, "modes"));
  const requiredFields = schemaRequiredFields("mode.schema.json");
  const observedModeIds = new Set();

  for (const filePath of modeFiles) {
    const mode = readJson(filePath);

    assertOnlyKnownTopLevelKeys(mode, "mode.schema.json", filePath);

    for (const field of requiredFields) {
      assert.ok(Object.hasOwn(mode, field), `${filePath} must contain ${field}`);
    }

    assert.match(mode.id, /^[a-z][a-z0-9-]*$/);
    assert.equal(typeof mode.label, "string");
    assert.equal(typeof mode.theme.accentPrimary, "string");
    assert.equal(typeof mode.theme.accentSecondary, "string");
    assert.ok(Array.isArray(mode.quickApps) && mode.quickApps.length >= 0 && mode.quickApps.length <= 5);
    assert.ok(Array.isArray(mode.quickActions) && mode.quickActions.length === 8);
    assert.equal(typeof mode.widgets.left, "string");
    assert.equal(typeof mode.widgets.right, "string");
    if (mode.id !== "executive") {
      assert.ok(mode.quickActions.includes(`open-${mode.id}-layout`));
    }
    observedModeIds.add(mode.id);
  }

  assert.deepEqual(observedModeIds, expectedModeIds);
});

test("current agent configs fit the agent schema surface", () => {
  const agentFiles = collectJsonFiles(path.join(configRoot, "agents"));
  const requiredFields = schemaRequiredFields("agent.schema.json");
  const observedAgentIds = new Set();

  for (const filePath of agentFiles) {
    const agent = readJson(filePath);

    assertOnlyKnownTopLevelKeys(agent, "agent.schema.json", filePath);

    for (const field of requiredFields) {
      assert.ok(Object.hasOwn(agent, field), `${filePath} must contain ${field}`);
    }

    assert.equal(agent.status, "mock");
    observedAgentIds.add(agent.id);
  }

  assert.deepEqual(observedAgentIds, expectedAgentIds);
});

test("safe extension fields are explicitly namespaced and preserved under extensions", () => {
  for (const schemaName of ["app-defaults.schema.json", "mode.schema.json", "mode-override.schema.json", "agent.schema.json", "settings-patch.schema.json"]) {
    const schema = readJson(path.join(schemasRoot, schemaName));
    const rawExtensionSchema =
      schemaName === "settings-patch.schema.json" ? schema.properties.changes.properties.extensions : schema.properties.extensions;
    const extensionSchema = resolveLocalRef(schema, rawExtensionSchema);

    assert.equal(extensionSchema.type, "object", `${schemaName} must expose an extensions object`);
    assert.deepEqual(extensionSchema.propertyNames, { pattern: "^x-[a-z][a-z0-9-]*$" });
    assert.equal(extensionSchema.additionalProperties, true);
  }
});

test("schemas do not expose direct risk weakening fields", () => {
  for (const schemaName of ["mode.schema.json", "mode-override.schema.json", "settings-patch.schema.json"]) {
    const schemaText = fs.readFileSync(path.join(schemasRoot, schemaName), "utf8");

    assert.equal(schemaText.includes("riskOverrides"), false);
    assert.equal(schemaText.includes("toolRiskOverrides"), false);
    assert.equal(schemaText.includes("requiresConfirmation"), false);
  }
});

test("invalid config fixtures represent rejected risk and extension behavior", () => {
  const riskOverrideMode = readJson(path.join(fixturesRoot, "invalid", "config", "modes", "risk-override.json"));
  const unsafeExtensionMode = readJson(path.join(fixturesRoot, "invalid", "config", "modes", "unsafe-extension-field.json"));
  const riskOverridePatch = readJson(path.join(fixturesRoot, "invalid", "config", "settings", "risk-override-patch.json"));

  assert.ok(Object.hasOwn(riskOverrideMode, "riskOverrides"));
  assert.ok(Object.hasOwn(unsafeExtensionMode, "unknownFutureField"));
  assert.ok(Object.hasOwn(riskOverridePatch.changes, "toolRiskOverrides"));
});

test("valid settings and validation-error fixtures cover supported shape", () => {
  const settingsPatch = readJson(path.join(fixturesRoot, "valid", "config", "settings", "default-mode-patch.json"));
  const validationError = readJson(path.join(fixturesRoot, "valid", "config", "validation-error", "mode-label-type.json"));

  for (const field of schemaRequiredFields("settings-patch.schema.json")) {
    assert.ok(Object.hasOwn(settingsPatch, field), `settings fixture must contain ${field}`);
  }

  for (const field of schemaRequiredFields("config-validation-error.schema.json")) {
    assert.ok(Object.hasOwn(validationError, field), `validation error fixture must contain ${field}`);
  }

  assert.equal(validationError.file, "modes/developer.json");
  assert.equal(validationError.field, "/label");
  assert.equal(validationError.expected, "string");
});

// The composer's editorial block cap sits BENEATH the report contract's own safety cap. The two
// live in different schema families and nothing else relates them, so a later widening of one
// could silently outrun the other — a composer allowed sixty-five blocks against a document that
// permits sixty-four is configuration that validates and then produces an invalid report.
test("the composer block cap can never exceed the report document's own", () => {
  const composerSchema = readJson(path.join(schemasRoot, "model-composer.schema.json"));
  const reportSchema = readJson(
    path.join(contractsRoot, "schemas", "reports", "report-document.schema.json")
  );

  const composerCap =
    composerSchema.$defs.composerReport.properties.composerMaxBlocks.maximum;
  const documentCap = reportSchema.properties.blocks.maxItems;

  assert.equal(typeof composerCap, "number");
  assert.equal(typeof documentCap, "number");
  assert.ok(
    composerCap <= documentCap,
    `composerMaxBlocks maximum (${composerCap}) must not exceed the report document's blocks cap (${documentCap})`
  );
});

// AC-11: a grammar over an under-constrained schema emits valid output forever — measured at 123
// blocks and 15,655 tokens before the context wall truncated the document mid-token. Requiring the
// cap in the SCHEMA is what stops a caller shipping without one, so the requirement is pinned here
// rather than left to whoever writes the next composer entry.
test("every composer entry is required to cap its output tokens", () => {
  const composerSchema = readJson(path.join(schemasRoot, "model-composer.schema.json"));
  const required = new Set(composerSchema.$defs.composerReport.required);

  assert.ok(required.has("composerMaxOutputTokens"));
  assert.ok(required.has("composerMaxBlocks"));
});
