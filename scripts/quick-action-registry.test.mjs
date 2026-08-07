import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { resolveRepositoryRoot } from "./workspace-roots.mjs";
import {
  readLayoutBackedWorkflowIds,
  readQuickActionRegistry,
  validateQuickActionRegistry
} from "./validate-config.mjs";

const repositoryRoot = resolveRepositoryRoot();

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

const configRoot = path.join(repositoryRoot, "config");

function registeredWorkflowIds() {
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

function registeredModeIds() {
  const modesDir = path.join(configRoot, "modes");
  return new Set(
    fs
      .readdirSync(modesDir)
      .filter((name) => name.endsWith(".json"))
      .map((name) => readJson(path.join(modesDir, name)).id)
  );
}

const workflowIds = registeredWorkflowIds();
const modeIds = registeredModeIds();

/** A minimal in-memory registry, so a case exercises one rule without touching the real file. */
function registry(actions, handlers = ["captureNote"]) {
  return {
    relativePath: "quickActions.registry.json",
    handlerNames: new Set(handlers),
    actions,
    actionIds: new Set(Object.keys(actions))
  };
}

function planned(overrides = {}) {
  return { label: "Daily brief", icon: "file-text", archetype: "report", ...overrides };
}

test("the real quick-action registry resolves every declared target", () => {
  const errors = [];
  validateQuickActionRegistry(readQuickActionRegistry(repositoryRoot), workflowIds, modeIds, errors);
  assert.deepEqual(errors, [], "every built quick action must resolve to a real workflow, handler, or layout");
});

test("every quick action a mode configures is registered", () => {
  const { actionIds } = readQuickActionRegistry(repositoryRoot);
  const modesDir = path.join(configRoot, "modes");

  for (const file of fs.readdirSync(modesDir).filter((name) => name.endsWith(".json"))) {
    for (const actionId of readJson(path.join(modesDir, file)).quickActions ?? []) {
      if (actionId === null) continue;
      assert.ok(actionIds.has(actionId), `modes/${file}: "${actionId}" is not in the dispatch registry`);
    }
  }
});

test("an action with no target is planned-not-built, not an error", () => {
  const errors = [];
  validateQuickActionRegistry(registry({ "daily-brief": planned() }), workflowIds, modeIds, errors);
  assert.deepEqual(errors, []);
});

test("an entry must declare a label, an icon, and a known archetype", () => {
  const errors = [];
  validateQuickActionRegistry(
    registry({ "daily-brief": { label: "", icon: "", archetype: "monitor" } }),
    workflowIds,
    modeIds,
    errors
  );

  assert.equal(errors.length, 3);
  assert.match(errors[0], /non-empty label/);
  assert.match(errors[1], /non-empty icon/);
  assert.match(errors[2], /must declare an archetype \(report, input, picker, fire-and-forget\)/);
});

test("a target pointing at a missing workflow is rejected with exact remediation", () => {
  const errors = [];
  validateQuickActionRegistry(
    registry({ "daily-brief": planned({ target: { kind: "workflow", workflow: "does-not-exist" } }) }),
    workflowIds,
    modeIds,
    errors
  );

  assert.equal(errors.length, 1);
  assert.match(errors[0], /action "daily-brief"/);
  assert.match(errors[0], /unknown workflow "does-not-exist"/);
  assert.match(errors[0], /config\/workflows/);
});

test("a target pointing at an undeclared handler is rejected with exact remediation", () => {
  const errors = [];
  validateQuickActionRegistry(
    registry({ "capture-note": planned({ target: { kind: "handler", handler: "noSuchHandler" } }) }),
    workflowIds,
    modeIds,
    errors
  );

  assert.equal(errors.length, 1);
  assert.match(errors[0], /action "capture-note"/);
  assert.match(errors[0], /unknown handler "noSuchHandler"/);
});

test("a layout target must name a real mode that actually has a layout", () => {
  const unknownMode = [];
  validateQuickActionRegistry(
    registry({ "open-x-layout": planned({ target: { kind: "layout", mode: "nope" } }) }),
    workflowIds,
    modeIds,
    unknownMode
  );
  assert.equal(unknownMode.length, 2, "an unknown mode has neither a mode file nor a layout");
  assert.match(unknownMode[0], /unknown mode "nope"/);

  // Executive is a real mode with no layout — a layout target at it must still fail, which the
  // old id-parsing regex could not detect at all (it only ever checked the id's shape).
  const noLayout = [];
  validateQuickActionRegistry(
    registry({ "open-executive-layout": planned({ target: { kind: "layout", mode: "executive" } }) }),
    new Set(["open-developer-layout"]),
    modeIds,
    noLayout
  );
  assert.equal(noLayout.length, 1);
  assert.match(noLayout[0], /which has no layout to open/);
});

test("an unknown target kind is rejected", () => {
  const errors = [];
  validateQuickActionRegistry(
    registry({ "daily-brief": planned({ target: { kind: "bridgeOp", op: "captureNote" } }) }),
    workflowIds,
    modeIds,
    errors
  );

  assert.equal(errors.length, 1);
  assert.match(errors[0], /target kind must be one of handler, workflow, layout/);
});
