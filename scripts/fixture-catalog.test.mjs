import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import { collectJsonFiles, readJson, repositoryRoot } from "./contracts-shared.mjs";

const catalogPath = path.join(repositoryRoot, "fixtures", "catalog", "canonical-states.json");
const configModesRoot = path.join(repositoryRoot, "config", "modes");

const expectedModeIds = new Set(["executive", "developer", "school", "entertainment"]);

const expectedCanonicalKeys = new Set([
  "mode.executive.ready",
  "mode.developer.ready",
  "mode.school.ready",
  "mode.entertainment.ready",
  "failure.configured_application_missing",
  "confirmation.shell.approved",
  "confirmation.denied",
  "confirmation.expired_or_plan_changed",
  "failure.tool_timeout",
  "failure.cancellation_during_execution",
  "failure.knowledge_root_missing",
  "failure.knowledge_root_read_only",
  "failure.sqlite_locked",
  "failure.bridge_major_version_mismatch",
  "failure.dashboard_offline",
  "system.metrics.loading",
  "system.metrics.stale",
  "system.metrics.unavailable",
  "system.metrics.disconnected",
  "future.external_provider_unavailable",
  "future.model_unavailable",
  "future.sensitive_context_blocked",
  "update.backup_failure",
  "update.migration_failure",
  "update.health_check_failure_rollback"
]);

const validDashboardStates = new Set([
  "loading",
  "empty",
  "stale",
  "unavailable",
  "offline",
  "error",
  "confirmation",
  "success",
  "cancelled",
  "ready"
]);

function catalog() {
  return readJson(catalogPath);
}

test("canonical fixture catalog covers every PRD fixture state", () => {
  const document = catalog();
  const keys = new Set(document.fixtures.map((fixture) => fixture.canonicalKey));

  assert.equal(document.schemaVersion, "1.0.0");
  assert.deepEqual(keys, expectedCanonicalKeys);
});

test("canonical fixtures use stable ids, clocks, and source references", () => {
  const ids = new Set();
  const keys = new Set();

  for (const fixture of catalog().fixtures) {
    assert.match(fixture.id, /^fx_[a-z0-9_]+$/, `${fixture.canonicalKey} has unstable id ${fixture.id}`);
    assert.match(fixture.clock, /^2026-06-23T16:[0-5][0-9]:00\.000Z$/, `${fixture.canonicalKey} has unstable clock ${fixture.clock}`);
    assert.equal(ids.has(fixture.id), false, `Duplicate fixture id ${fixture.id}`);
    assert.equal(keys.has(fixture.canonicalKey), false, `Duplicate fixture key ${fixture.canonicalKey}`);
    ids.add(fixture.id);
    keys.add(fixture.canonicalKey);

    for (const sourceFixture of fixture.sourceFixtures ?? []) {
      const sourcePath = path.join(repositoryRoot, sourceFixture);
      assert.equal(fs.existsSync(sourcePath), true, `${fixture.canonicalKey} references missing source fixture ${sourceFixture}`);
    }
  }
});

test("mode fixtures cover the configured MVP modes", () => {
  const configuredModeIds = new Set(collectJsonFiles(configModesRoot).map((filePath) => readJson(filePath).id));
  const catalogModeIds = new Set(
    catalog()
      .fixtures.filter((fixture) => fixture.category === "mode")
      .map((fixture) => fixture.modeId)
  );

  assert.deepEqual(configuredModeIds, expectedModeIds);
  assert.deepEqual(catalogModeIds, expectedModeIds);
});

test("dashboard fixtures are story-ready and come from the canonical catalog", () => {
  const dashboardFixtures = catalog().fixtures.filter((fixture) => fixture.dashboardState);

  assert.ok(dashboardFixtures.length >= 2, "Catalog should include ready and degraded dashboard states.");

  for (const fixture of dashboardFixtures) {
    assert.equal(validDashboardStates.has(fixture.dashboardState.uiState), true, `${fixture.canonicalKey} has invalid UI state.`);
    assert.equal(typeof fixture.dashboardState.summary, "string");
    assert.equal(typeof fixture.dashboardState.activeSurface, "string");
    assert.equal(Number.isInteger(fixture.dashboardState.commandsToday), true);
    assert.equal(Number.isInteger(fixture.dashboardState.pendingConfirmations), true);
  }
});
