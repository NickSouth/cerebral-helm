import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { resolveRepositoryRoot } from "./workspace-roots.mjs";
import {
  readRegisteredQuickAppIds,
  readRegisteredWidgetIds,
  validateModeQuickApps,
  validateModeWidgets
} from "./validate-config.mjs";

const repositoryRoot = resolveRepositoryRoot();
const registeredWidgetIds = readRegisteredWidgetIds(repositoryRoot);
const registeredAppIds = readRegisteredQuickAppIds(repositoryRoot);

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function modeConfigFiles() {
  const modesDir = path.join(repositoryRoot, "config", "modes");
  return fs.readdirSync(modesDir).filter((file) => file.endsWith(".json"));
}

test("the widget manifest registers exactly the eight design-spec widget slots", () => {
  assert.deepEqual(
    [...registeredWidgetIds].sort(),
    [
      "courses",
      "deadlines",
      "market-brief",
      "project-git-status",
      "projects",
      "releases",
      "repositories",
      "spotify"
    ]
  );
});

test("the application catalog registers every quick-app the real modes reference", () => {
  const modesDir = path.join(repositoryRoot, "config", "modes");
  const referenced = new Set();

  for (const file of modeConfigFiles()) {
    for (const appId of readJson(path.join(modesDir, file)).quickApps ?? []) {
      referenced.add(appId);
    }
  }

  for (const appId of referenced) {
    assert.ok(registeredAppIds.has(appId), `quick-app "${appId}" must be in the application catalog`);
  }
});

test("every real mode config resolves its widget slots and quick apps", () => {
  const modesDir = path.join(repositoryRoot, "config", "modes");

  for (const file of modeConfigFiles()) {
    const document = readJson(path.join(modesDir, file));
    const errors = [];
    validateModeWidgets(document, `modes/${file}`, registeredWidgetIds, errors);
    validateModeQuickApps(document, `modes/${file}`, registeredAppIds, errors);
    assert.deepEqual(errors, [], `${file} should resolve all widget and quick-app references`);
  }
});

test("an unresolved widget id is rejected with exact remediation", () => {
  const fixture = readJson(
    path.join(repositoryRoot, "packages", "contracts", "fixtures", "invalid", "config", "modes", "unresolved-widget.json")
  );
  const errors = [];

  validateModeWidgets(fixture, "modes/unresolved-widget.json", registeredWidgetIds, errors);

  assert.equal(errors.length, 1);
  assert.match(errors[0], /widgets\.right "leaderboard"/);
  assert.match(errors[0], /registered widget/);
  assert.match(errors[0], /widgets\.manifest\.json/);
});

test("an unresolved quick-app id is rejected with exact remediation", () => {
  const fixture = readJson(
    path.join(repositoryRoot, "packages", "contracts", "fixtures", "invalid", "config", "modes", "unresolved-quick-app.json")
  );
  const errors = [];

  validateModeQuickApps(fixture, "modes/unresolved-quick-app.json", registeredAppIds, errors);

  assert.equal(errors.length, 1);
  assert.match(errors[0], /quickApps entry "myspace"/);
  assert.match(errors[0], /registered application/);
  assert.match(errors[0], /appCatalog\.manifest\.json/);
});
