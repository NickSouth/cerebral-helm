import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { resolveRepositoryRoot } from "./workspace-roots.mjs";

const repositoryRoot = resolveRepositoryRoot();
const contractsRoot = path.join(repositoryRoot, "packages", "contracts");
const schemasRoot = path.join(contractsRoot, "schemas", "commands");
const fixturesRoot = path.join(contractsRoot, "fixtures");

const commandSources = new Set(["dashboard", "hotkey", "cli", "automation", "system", "voice", "ios", "agent"]);
const validTransitions = new Set([
  "null->received",
  "received->planned",
  "planned->requires_confirmation",
  "planned->running",
  "requires_confirmation->running",
  "requires_confirmation->cancelled",
  "running->succeeded",
  "running->failed",
  "running->cancelled"
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

function transitionKey(event) {
  return `${event.previousStatus ?? "null"}->${event.currentStatus}`;
}

test("command schemas are present and parse as JSON Schema documents", () => {
  for (const schemaName of [
    "command-envelope.schema.json",
    "command-lifecycle-event.schema.json",
    "command-terminal-result.schema.json",
    "structured-error.schema.json"
  ]) {
    const schema = readJson(path.join(schemasRoot, schemaName));

    assert.equal(schema.$schema, "https://json-schema.org/draft/2020-12/schema");
    assert.match(schema.$id, /^https:\/\/cerebralhelm\.local\/schemas\/commands\//);
  }
});

test("command envelope schema includes MVP and reserved future sources", () => {
  const schema = readJson(path.join(schemasRoot, "command-envelope.schema.json"));
  const sourceValues = new Set(schema.properties.source.enum);

  assert.deepEqual(sourceValues, commandSources);
});

test("valid command envelope fixtures cover every supported source with stable clocks", () => {
  const fixtureFiles = collectJsonFiles(path.join(fixturesRoot, "valid", "commands"));
  const observedSources = new Set();

  for (const filePath of fixtureFiles) {
    const fixture = readJson(filePath);

    assert.match(fixture.id, /^cmd_[A-Za-z0-9_-]{8,64}$/);
    assert.match(fixture.timestamp, /^2026-06-23T16:00:\d{2}\.000Z$/);
    assert.ok(commandSources.has(fixture.source), `${filePath} has unexpected source ${fixture.source}`);
    observedSources.add(fixture.source);
  }

  assert.deepEqual(observedSources, commandSources);
});

test("lifecycle schema and valid fixtures cover every allowed transition", () => {
  const schema = readJson(path.join(schemasRoot, "command-lifecycle-event.schema.json"));
  const schemaTransitions = new Set(
    schema.oneOf.map((entry) => {
      const previousStatus = entry.properties.previousStatus.const ?? "null";
      return `${previousStatus}->${entry.properties.currentStatus.const}`;
    })
  );
  const fixtureTransitions = new Set(
    collectJsonFiles(path.join(fixturesRoot, "valid", "lifecycle")).map((filePath) => transitionKey(readJson(filePath)))
  );

  assert.deepEqual(schemaTransitions, validTransitions);
  assert.deepEqual(fixtureTransitions, validTransitions);
});

test("invalid lifecycle fixtures represent rejected transition pairs", () => {
  const invalidTransitionFiles = collectJsonFiles(path.join(fixturesRoot, "invalid", "lifecycle"));

  assert.ok(invalidTransitionFiles.length >= 2);

  for (const filePath of invalidTransitionFiles) {
    const fixture = readJson(filePath);

    assert.equal(validTransitions.has(transitionKey(fixture)), false, `${filePath} must remain an invalid transition fixture`);
  }
});

test("invalid command fixtures represent rejected command sources", () => {
  const invalidCommandFiles = collectJsonFiles(path.join(fixturesRoot, "invalid", "commands"));

  assert.ok(invalidCommandFiles.length >= 1);

  for (const filePath of invalidCommandFiles) {
    const fixture = readJson(filePath);

    assert.equal(commandSources.has(fixture.source), false, `${filePath} must remain an invalid source fixture`);
  }
});
