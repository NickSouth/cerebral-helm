import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { validateRepositoryConfig } from "./validate-config.mjs";
import {
  describeRoots,
  resolveDatabasePath,
  resolveEventLogPath,
  resolveRepositoryRoot,
  resolveSimulationOutputRoot,
  resolveStateRoot
} from "./workspace-roots.mjs";

test("repository config validates", () => {
  const summary = validateRepositoryConfig();

  assert.equal(summary.modeCount, 4);
  assert.equal(summary.agentCount, 4);
  assert.equal(summary.toolCount, 6);
});

test("development roots stay inside the repository", () => {
  const repositoryRoot = resolveRepositoryRoot();
  const normalizedRepositoryRoot = path.normalize(repositoryRoot + path.sep);

  for (const candidate of [
    resolveStateRoot(),
    resolveDatabasePath(),
    resolveEventLogPath(),
    resolveSimulationOutputRoot()
  ]) {
    const normalizedCandidate = path.normalize(candidate);
    assert.ok(
      normalizedCandidate.startsWith(normalizedRepositoryRoot),
      `${candidate} must stay inside ${repositoryRoot}`
    );
  }
});

test("simulation fixture exists for the default command", () => {
  const { fixtureRoot } = describeRoots();
  const fixturePath = path.join(fixtureRoot, "simulations", "successful-developer-mode.json");

  assert.equal(fs.existsSync(fixturePath), true);
});
