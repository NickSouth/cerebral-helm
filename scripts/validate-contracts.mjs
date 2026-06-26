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

  if (relativePath.startsWith("invalid/config/modes/")) {
    return schemaId("config", "mode");
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
    }))
  ];
}

export function validateContracts() {
  const ajv = createAjv();
  const errors = [];
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
  }

  for (const filePath of invalidFixtures) {
    const schema = schemaForFixture(filePath);

    if (!schema) {
      errors.push(`${path.relative(repositoryRoot, filePath)} has no validation schema mapping.`);
      continue;
    }

    validateDocument(ajv, filePath, schema, errors, false);
  }

  for (const example of currentConfigExamples()) {
    validateDocument(ajv, example.filePath, example.schema, errors, true);
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
