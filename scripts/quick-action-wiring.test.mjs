import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { resolveRepositoryRoot } from "./workspace-roots.mjs";
import { readLayoutBackedWorkflowIds, readQuickActionWiring, validateQuickActionWiring } from "./validate-config.mjs";

const repositoryRoot = resolveRepositoryRoot();

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function registeredWorkflowIds() {
  const configRoot = path.join(repositoryRoot, "config");
  const workflowsDir = path.join(configRoot, "workflows");
  const ids = new Set();
  for (const file of fs.readdirSync(workflowsDir).filter((name) => name.endsWith(".json"))) {
    ids.add(readJson(path.join(workflowsDir, file)).id);
  }
  // Layout-backed actions (open-<mode>-layout) are synthesized from a mode's
  // authored layout, not a static workflow file — resolve them the same way.
  for (const id of readLayoutBackedWorkflowIds(configRoot)) {
    ids.add(id);
  }
  return ids;
}

const workflowIds = registeredWorkflowIds();

test("the real quick-action wiring manifest resolves every wired target", () => {
  const errors = [];
  validateQuickActionWiring(readQuickActionWiring(repositoryRoot), workflowIds, errors);
  assert.deepEqual(errors, [], "every wired quick action must resolve to a real workflow or handler");
});

test("a wired action pointing at a missing workflow is rejected with exact remediation", () => {
  const wiring = {
    relativePath: "quickActions.manifest.json",
    handlerNames: new Set(["captureNote"]),
    wiredActions: { "daily-brief": { workflow: "does-not-exist" } }
  };
  const errors = [];

  validateQuickActionWiring(wiring, workflowIds, errors);

  assert.equal(errors.length, 1);
  assert.match(errors[0], /wired action "daily-brief"/);
  assert.match(errors[0], /unknown workflow "does-not-exist"/);
  assert.match(errors[0], /config\/workflows/);
});

test("a wired action pointing at an undeclared handler is rejected with exact remediation", () => {
  const wiring = {
    relativePath: "quickActions.manifest.json",
    handlerNames: new Set(["captureNote"]),
    wiredActions: { "capture-note": { handler: "noSuchHandler" } }
  };
  const errors = [];

  validateQuickActionWiring(wiring, workflowIds, errors);

  assert.equal(errors.length, 1);
  assert.match(errors[0], /wired action "capture-note"/);
  assert.match(errors[0], /unknown handler "noSuchHandler"/);
});

test("a wired action must declare exactly one of workflow or handler", () => {
  const handlerNames = new Set(["captureNote"]);

  const neither = [];
  validateQuickActionWiring(
    { relativePath: "m.json", handlerNames, wiredActions: { "x": {} } },
    workflowIds,
    neither
  );
  assert.equal(neither.length, 1);
  assert.match(neither[0], /exactly one of workflow or handler/);

  const both = [];
  validateQuickActionWiring(
    { relativePath: "m.json", handlerNames, wiredActions: { "x": { workflow: "open-executive-layout", handler: "captureNote" } } },
    workflowIds,
    both
  );
  assert.equal(both.length, 1);
  assert.match(both[0], /exactly one of workflow or handler/);
});

test("a workflow-backed wired action resolves against config/workflows ids", () => {
  // Proves the workflow path is live (not just the handler path the real manifest uses).
  const wiring = {
    relativePath: "m.json",
    handlerNames: new Set(),
    wiredActions: { "open-exec": { workflow: "open-executive-layout" } }
  };
  const errors = [];

  validateQuickActionWiring(wiring, workflowIds, errors);

  assert.deepEqual(errors, []);
});
