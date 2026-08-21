import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync, readdirSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

// NIC-127 Increment 5: the per-mode news relevance config (config/news/profiles.json) is well
// formed and covers every mode's `newsProfile`, so no mode silently falls back to the default.

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const readJson = (p) => JSON.parse(readFileSync(p, "utf8"));

test("news profiles config is well formed", () => {
  const config = readJson(path.join(repoRoot, "config/news/profiles.json"));
  assert.equal(typeof config.language, "string");
  assert.ok(config.language.length > 0, "language must be non-empty");
  assert.equal(typeof config.defaultCategory, "string");
  assert.ok(config.defaultCategory.length > 0, "defaultCategory must be non-empty");
  assert.equal(typeof config.profiles, "object");
  // NIC-223: the interest `q=` switch. Optional (an older file decodes without it and keeps the
  // default), but a typo must not silently disable the feature — the Swift catalog treats anything
  // that is not exactly "q" as off.
  if ("interestQuery" in config) {
    assert.ok(
      ["q", "off"].includes(config.interestQuery),
      `interestQuery must be "q" or "off", got ${JSON.stringify(config.interestQuery)}`
    );
  }
  for (const [profile, category] of Object.entries(config.profiles)) {
    assert.equal(typeof category, "string", `profile ${profile} must map to a string`);
    assert.ok(category.length > 0, `profile ${profile} must map to a non-empty category`);
  }
});

test("every mode's newsProfile has an explicit category mapping", () => {
  const config = readJson(path.join(repoRoot, "config/news/profiles.json"));
  const modesDir = path.join(repoRoot, "config/modes");
  const modeFiles = readdirSync(modesDir).filter((f) => f.endsWith(".json"));
  assert.ok(modeFiles.length > 0, "expected mode config files");

  const uncovered = [];
  for (const file of modeFiles) {
    const mode = readJson(path.join(modesDir, file));
    if (mode.newsProfile && !(mode.newsProfile in config.profiles)) {
      uncovered.push(`${mode.id ?? file}:${mode.newsProfile}`);
    }
  }
  assert.deepEqual(
    uncovered,
    [],
    `every mode newsProfile must be mapped in config/news/profiles.json; unmapped: ${uncovered.join(", ")}`
  );
});
