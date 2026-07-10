import path from "node:path";
import Ajv2020 from "ajv/dist/2020.js";
import {
  collectJsonFiles,
  collectSchemaFiles,
  contractsRoot,
  fixturesRoot,
  invokedDirectly,
  readJson,
  repositoryRoot,
  schemasRoot
} from "./contracts-shared.mjs";
import {
  readRegisteredModeThemeTokens,
  readRegisteredQuickAppIds,
  readRegisteredWidgetIds,
  validateModeQuickApps,
  validateModeThemeTokens,
  validateModeWidgets
} from "./validate-config.mjs";

// A mode reference fixture (theme token / widget / quick-app) is schema-valid by
// construction — the dangling id still matches the configId pattern — so JSON Schema
// alone cannot reject it. The reference-resolution gate is the constraint "JSON Schema
// cannot express", so an invalid mode fixture is allowed to fail via this gate, exactly
// as reference-catalog and workflow fixtures may fail via their duplicate-id scans.
function readModeReferenceRegistries() {
  return {
    tokenNames: readRegisteredModeThemeTokens(repositoryRoot),
    widgetIds: readRegisteredWidgetIds(repositoryRoot),
    appIds: readRegisteredQuickAppIds(repositoryRoot)
  };
}

function modeReferenceGateErrors(filePath, registries) {
  const document = readJson(filePath);
  const relativePath = path.relative(repositoryRoot, filePath);
  const errors = [];
  validateModeThemeTokens(document, relativePath, registries.tokenNames, errors);
  validateModeWidgets(document, relativePath, registries.widgetIds, errors);
  validateModeQuickApps(document, relativePath, registries.appIds, errors);
  return errors;
}

function fail(message) {
  throw new Error(message);
}

function schemaId(group, name) {
  return `https://cerebralhelm.local/schemas/${group}/${name}.schema.json`;
}

function createAjv() {
  const ajv = new Ajv2020({
    allErrors: true,
    strict: false,
    validateFormats: false
  });

  for (const filePath of collectSchemaFiles()) {
    const schema = readJson(filePath);
    ajv.addSchema(schema, schema.$id);
  }

  return ajv;
}

function formatErrors(filePath, errors) {
  return (errors ?? []).map((error) => {
    const instancePath = error.instancePath || "/";
    return `${path.relative(repositoryRoot, filePath)} ${instancePath} failed ${error.schemaPath}: ${error.message}`;
  });
}

function validateDocument(ajv, filePath, schema, errors, shouldPass) {
  const validate = ajv.getSchema(schema);

  if (!validate) {
    errors.push(`${path.relative(repositoryRoot, filePath)} references unknown schema ${schema}`);
    return;
  }

  const valid = validate(readJson(filePath));

  if (shouldPass && !valid) {
    errors.push(...formatErrors(filePath, validate.errors));
  }

  if (!shouldPass && valid) {
    errors.push(`${path.relative(repositoryRoot, filePath)} unexpectedly passed ${schema}`);
  }
}

function schemaForFixture(filePath) {
  const relativePath = path.relative(fixturesRoot, filePath).replaceAll("\\", "/");

  if (relativePath.startsWith("valid/commands/") || relativePath.startsWith("invalid/commands/")) {
    return schemaId("commands", "command-envelope");
  }

  if (relativePath.startsWith("valid/lifecycle/") || relativePath.startsWith("invalid/lifecycle/")) {
    return schemaId("commands", "command-lifecycle-event");
  }

  if (relativePath.startsWith("valid/results/")) {
    return schemaId("commands", "command-terminal-result");
  }

  if (relativePath.startsWith("valid/tools/descriptors/") || relativePath.startsWith("invalid/tools/descriptors/")) {
    return schemaId("tools", "tool-descriptor");
  }

  if (relativePath.startsWith("valid/tools/io/") || relativePath.startsWith("invalid/tools/io/")) {
    return schemaId("tools", path.basename(relativePath, ".json"));
  }

  if (relativePath.startsWith("valid/tools/confirmations/")) {
    return schemaId("tools", "confirmation-disclosure");
  }

  if (relativePath.startsWith("valid/tools/results/")) {
    return schemaId("tools", "tool-result");
  }

  if (relativePath.startsWith("valid/config/settings/") || relativePath.startsWith("invalid/config/settings/")) {
    return schemaId("config", "settings-patch");
  }

  if (relativePath.startsWith("valid/config/validation-error/")) {
    return schemaId("config", "config-validation-error");
  }

  if (relativePath.startsWith("valid/config/modes/") || relativePath.startsWith("invalid/config/modes/")) {
    return schemaId("config", "mode");
  }

  if (relativePath.startsWith("valid/config/overrides/") || relativePath.startsWith("invalid/config/overrides/")) {
    return schemaId("config", "mode-override");
  }

  if (relativePath.startsWith("valid/references/") || relativePath.startsWith("invalid/references/")) {
    return schemaId("references", "reference-catalog");
  }

  if (relativePath.startsWith("valid/workflows/") || relativePath.startsWith("invalid/workflows/")) {
    return schemaId("workflows", "workflow");
  }

  if (relativePath.startsWith("valid/knowledge/") || relativePath.startsWith("invalid/knowledge/")) {
    return schemaId("knowledge", "note-metadata");
  }

  if (relativePath.includes("/bridge/handshake/request.json")) {
    return schemaId("bridge", "handshake-request");
  }

  if (relativePath.includes("/bridge/handshake/")) {
    return schemaId("bridge", "handshake-response");
  }

  if (relativePath.includes("/bridge/bootstrap/")) {
    return schemaId("bridge", "bootstrap-state");
  }

  if (relativePath.includes("/bridge/settings/")) {
    return schemaId("bridge", "settings-snapshot");
  }

  if (relativePath.includes("/bridge/operations/") && relativePath.endsWith("-request.json")) {
    return schemaId("bridge", "operation-request");
  }

  if (relativePath.includes("/bridge/operations/") && relativePath.endsWith("-response.json")) {
    return schemaId("bridge", "operation-response");
  }

  if (relativePath.includes("/bridge/events/")) {
    return schemaId("bridge", "event");
  }

  return null;
}

function currentConfigExamples() {
  const configRoot = path.join(repositoryRoot, "config");

  return [
    {
      filePath: path.join(configRoot, "defaults", "app.json"),
      schema: schemaId("config", "app-defaults")
    },
    ...collectJsonFiles(path.join(configRoot, "modes")).map((filePath) => ({
      filePath,
      schema: schemaId("config", "mode")
    })),
    ...collectJsonFiles(path.join(configRoot, "agents")).map((filePath) => ({
      filePath,
      schema: schemaId("config", "agent")
    })),
    ...collectJsonFiles(path.join(configRoot, "tools", "descriptors")).map((filePath) => ({
      filePath,
      schema: schemaId("tools", "tool-descriptor")
    })),
    ...collectJsonFiles(path.join(configRoot, "references")).map((filePath) => ({
      filePath,
      schema: schemaId("references", "reference-catalog")
    }))
  ];
}

// JSON Schema cannot dedupe array entries by an object key, so duplicate
// reference ids would otherwise be silently dropped at runtime. Scan each
// reference catalog and treat any repeated id as a hard validation error,
// mirroring the cross-file id checks already performed elsewhere.
function scanReferenceCatalogDuplicateIds(filePath, errors) {
  const document = readJson(filePath);
  const references = Array.isArray(document.references) ? document.references : [];
  const seen = new Set();

  for (const reference of references) {
    const id = reference?.id;

    if (typeof id !== "string") {
      continue;
    }

    if (seen.has(id)) {
      errors.push(`${path.relative(repositoryRoot, filePath)} declares duplicate reference id "${id}".`);
    }

    seen.add(id);
  }
}

// JSON Schema cannot dedupe array entries by an object key, so a workflow that
// repeats a step id would be ambiguous to the planner. Scan each workflow and
// treat any repeated step id as a hard validation error, mirroring the
// reference-catalog duplicate-id check.
function scanWorkflowDuplicateStepIds(filePath, errors) {
  const document = readJson(filePath);
  const steps = Array.isArray(document.steps) ? document.steps : [];
  const seen = new Set();

  for (const step of steps) {
    const id = step?.id;

    if (typeof id !== "string") {
      continue;
    }

    if (seen.has(id)) {
      errors.push(`${path.relative(repositoryRoot, filePath)} declares duplicate workflow step id "${id}".`);
    }

    seen.add(id);
  }
}

export function validateContracts() {
  const ajv = createAjv();
  const errors = [];
  const modeReferenceRegistries = readModeReferenceRegistries();
  const validFixtures = collectJsonFiles(path.join(fixturesRoot, "valid"));
  const invalidFixtures = collectJsonFiles(path.join(fixturesRoot, "invalid"));

  for (const schemaPath of collectSchemaFiles()) {
    const schema = readJson(schemaPath);
    const validate = ajv.getSchema(schema.$id);

    if (!validate) {
      errors.push(`${path.relative(repositoryRoot, schemaPath)} did not compile with Ajv.`);
    }
  }

  for (const filePath of validFixtures) {
    const schema = schemaForFixture(filePath);

    if (!schema) {
      errors.push(`${path.relative(repositoryRoot, filePath)} has no validation schema mapping.`);
      continue;
    }

    validateDocument(ajv, filePath, schema, errors, true);

    if (schema === schemaId("references", "reference-catalog")) {
      scanReferenceCatalogDuplicateIds(filePath, errors);
    }

    if (schema === schemaId("workflows", "workflow")) {
      scanWorkflowDuplicateStepIds(filePath, errors);
    }
  }

  for (const filePath of invalidFixtures) {
    const schema = schemaForFixture(filePath);

    if (!schema) {
      errors.push(`${path.relative(repositoryRoot, filePath)} has no validation schema mapping.`);
      continue;
    }

    // Reference catalogs can be invalid either structurally (caught by Ajv) or
    // because they declare duplicate ids (caught by the duplicate-id scan, which
    // JSON Schema cannot express). Accept either signal as the expected failure.
    if (schema === schemaId("references", "reference-catalog")) {
      const validate = ajv.getSchema(schema);
      const ajvValid = validate ? validate(readJson(filePath)) : false;
      const duplicateErrors = [];
      scanReferenceCatalogDuplicateIds(filePath, duplicateErrors);

      if (ajvValid && duplicateErrors.length === 0) {
        errors.push(`${path.relative(repositoryRoot, filePath)} unexpectedly passed ${schema}`);
      }

      continue;
    }

    // Workflows can be invalid structurally (Ajv) or by repeating a step id
    // (the duplicate-step scan, which JSON Schema cannot express). Accept either.
    if (schema === schemaId("workflows", "workflow")) {
      const validate = ajv.getSchema(schema);
      const ajvValid = validate ? validate(readJson(filePath)) : false;
      const duplicateErrors = [];
      scanWorkflowDuplicateStepIds(filePath, duplicateErrors);

      if (ajvValid && duplicateErrors.length === 0) {
        errors.push(`${path.relative(repositoryRoot, filePath)} unexpectedly passed ${schema}`);
      }

      continue;
    }

    // Modes can be invalid structurally (Ajv) or by referencing an unregistered
    // theme token / widget / quick-app (the reference-resolution gate, which JSON
    // Schema cannot express). Accept either signal as the expected failure.
    if (schema === schemaId("config", "mode")) {
      const validate = ajv.getSchema(schema);
      const ajvValid = validate ? validate(readJson(filePath)) : false;
      const gateErrors = modeReferenceGateErrors(filePath, modeReferenceRegistries);

      if (ajvValid && gateErrors.length === 0) {
        errors.push(`${path.relative(repositoryRoot, filePath)} unexpectedly passed ${schema}`);
      }

      continue;
    }

    validateDocument(ajv, filePath, schema, errors, false);
  }

  for (const example of currentConfigExamples()) {
    validateDocument(ajv, example.filePath, example.schema, errors, true);

    if (example.schema === schemaId("references", "reference-catalog")) {
      scanReferenceCatalogDuplicateIds(example.filePath, errors);
    }
  }

  if (errors.length > 0) {
    fail(`Contract validation failed:\n- ${errors.join("\n- ")}`);
  }

  return {
    schemaCount: collectSchemaFiles().length,
    validFixtureCount: validFixtures.length,
    invalidFixtureCount: invalidFixtures.length,
    contractRoot: contractsRoot
  };
}

export function main() {
  const summary = validateContracts();

  console.log(
    `Validated ${summary.schemaCount} schemas, ${summary.validFixtureCount} valid fixtures, and ${summary.invalidFixtureCount} invalid fixtures.`
  );
  console.log(`Contracts root: ${summary.contractRoot}`);
}

if (invokedDirectly(import.meta.url)) {
  main();
}
