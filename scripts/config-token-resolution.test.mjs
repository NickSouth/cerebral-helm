import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { resolveRepositoryRoot } from "./workspace-roots.mjs";
import { readRegisteredModeThemeTokens, validateModeThemeTokens } from "./validate-config.mjs";

const repositoryRoot = resolveRepositoryRoot();
const registeredTokenNames = readRegisteredModeThemeTokens(repositoryRoot);

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

test("the token manifest registers exactly the eight mode theme tokens", () => {
  assert.deepEqual(
    [...registeredTokenNames].sort(),
    [
      "developer.primary",
      "developer.secondary",
      "entertainment.primary",
      "entertainment.secondary",
      "executive.primary",
      "executive.secondary",
      "school.primary",
      "school.secondary"
    ]
  );
});

test("every real mode config resolves its theme tokens", () => {
  const modesDir = path.join(repositoryRoot, "config", "modes");
  const modeFiles = fs.readdirSync(modesDir).filter((file) => file.endsWith(".json"));

  assert.ok(modeFiles.length > 0, "expected at least one mode config");

  for (const file of modeFiles) {
    const errors = [];
    validateModeThemeTokens(readJson(path.join(modesDir, file)), `modes/${file}`, registeredTokenNames, errors);
    assert.deepEqual(errors, [], `${file} should resolve all theme tokens`);
  }
});

test("an unresolved theme token is rejected with exact remediation", () => {
  const fixture = readJson(
    path.join(
      repositoryRoot,
      "packages",
      "contracts",
      "fixtures",
      "invalid",
      "config",
      "modes",
      "unresolved-theme-token.json"
    )
  );
  const errors = [];

  validateModeThemeTokens(fixture, "modes/unresolved-theme-token.json", registeredTokenNames, errors);

  assert.equal(errors.length, 1);
  assert.match(errors[0], /executive\.tertiary/);
  assert.match(errors[0], /registered design token/);
  assert.match(errors[0], /tokens\.manifest\.json/);
});
