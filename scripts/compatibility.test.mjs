import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { validateCompatibilityManifest } from "./validate-compatibility.mjs";
import { resolveRepositoryRoot } from "./workspace-roots.mjs";

test("compatibility manifest validates", () => {
  const summary = validateCompatibilityManifest();

  assert.equal(summary.contractCount, 6);
  assert.equal(summary.providerCount, 2);
});

test("compatibility manifest and schema files exist", () => {
  const repositoryRoot = resolveRepositoryRoot();

  for (const targetPath of [
    path.join(repositoryRoot, "docs", "compatibility", "compatibility-manifest.json"),
    path.join(repositoryRoot, "docs", "compatibility", "compatibility-manifest.schema.json")
  ]) {
    assert.equal(fs.existsSync(targetPath), true);
  }
});
