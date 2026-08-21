// Keeps the report document schema BOUNDED.
//
// This schema is the one a model generates wholesale under a grammar, and that makes
// an unbounded dimension here a different kind of defect than it is anywhere else. A
// grammar enforces exactly what the schema says while removing the model's incentive
// to be plausible, so whatever the schema forgets to forbid becomes reachable: one
// measured composition produced 123 blocks — `line`/`metric` alternating, every
// optional field filled, `leaderboardPreview: 1000000000000000` — until it exhausted
// the context and truncated mid-token. A truncated document is UNPARSEABLE rather
// than invalid, so schema validation downstream does not even diagnose it.
//
// Deliberately scoped to this one schema. Tool input schemas are NOT held to this
// rule and should not be: `note.capture`'s `body` is legitimately unbounded, and an
// over-long tool argument is rejected by validation rather than corrupting a surface.
// The difference is that a tool call is checked before it executes, and a report is
// rendered.

import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { resolveRepositoryRoot } from "./workspace-roots.mjs";

const schemaPath = path.join(
  resolveRepositoryRoot(),
  "packages/contracts/schemas/reports/report-document.schema.json"
);
const schema = JSON.parse(fs.readFileSync(schemaPath, "utf8"));

/// Walks every genuine subschema. Maps of author-chosen names (`properties`, `$defs`)
/// are traversed but never treated as schemas themselves.
const SCHEMA_MAP_KEYWORDS = new Set(["properties", "$defs", "definitions", "patternProperties"]);

function* subschemas(node, pointer = "") {
  if (node === null || typeof node !== "object" || Array.isArray(node)) return;
  yield [pointer || "/", node];
  for (const [key, value] of Object.entries(node)) {
    if (value === null || typeof value !== "object") continue;
    if (SCHEMA_MAP_KEYWORDS.has(key) && !Array.isArray(value)) {
      for (const [name, sub] of Object.entries(value)) yield* subschemas(sub, `${pointer}/${key}/${name}`);
      continue;
    }
    if (Array.isArray(value)) continue;
    yield* subschemas(value, `${pointer}/${key}`);
  }
}

test("every array in the report schema declares maxItems", () => {
  const unbounded = [];
  for (const [pointer, node] of subschemas(schema)) {
    if (node.type === "array" && node.maxItems === undefined) unbounded.push(pointer);
  }
  assert.deepEqual(
    unbounded,
    [],
    "An unbounded array is an unbounded generation once a grammar drives this schema."
  );
});

test("every free-text string in the report schema declares maxLength", () => {
  const unbounded = [];
  for (const [pointer, node] of subschemas(schema)) {
    // An enum is already bounded to its own vocabulary, and a `const` to one value.
    if (node.type !== "string") continue;
    if (node.enum || node.const) continue;
    if (node.maxLength === undefined) unbounded.push(pointer);
  }
  assert.deepEqual(unbounded, [], "An unbounded string can absorb a whole context window.");
});

test("every integer in the report schema declares a maximum", () => {
  const unbounded = [];
  for (const [pointer, node] of subschemas(schema)) {
    if (node.type === "integer" && node.maximum === undefined) unbounded.push(pointer);
  }
  assert.deepEqual(
    unbounded,
    [],
    "`leaderboardPreview` had a minimum and no maximum, and a grammar duly emitted 1000000000000000."
  );
});

test("the bounds that carry meaning rather than safety margin", () => {
  const block = schema.$defs.reportBlock.properties;

  // Semantic, not a margin: a scoreboard is two sides, away first.
  assert.equal(block.scoreboardSides.maxItems, 2);

  // Deliberately generous. This array is the COMPLETE field rather than a preview —
  // `leaderboardPreview` decides how many render — so a bound tight enough to look
  // tidy would break expanding without a refetch. A full golf field runs to ~156.
  assert.ok(
    block.leaderboardRows.maxItems >= 200,
    "leaderboardRows must stay generous enough to hold a complete field"
  );

  // Comfortably above every deterministic composer (all well under 30) and far below
  // the 123 blocks a grammar produced unbounded.
  assert.ok(
    schema.properties.blocks.maxItems >= 32 && schema.properties.blocks.maxItems <= 128,
    "blocks cap should bound a runaway without constraining a real report"
  );
});

test("the block shape stays FLAT, not a discriminated union", () => {
  // Guarding a documented decision, not an accident: a union would make adding a
  // block kind a breaking contract change, and the renderer is built to survive a
  // malformed block once a model writes these — it skips a kind it does not know.
  // Bounding the schema was the correct answer to the runaway; unioning it was not.
  const block = schema.$defs.reportBlock;
  for (const keyword of ["oneOf", "anyOf", "allOf", "if", "then", "else"]) {
    assert.ok(!(keyword in block), `reportBlock should not use ${keyword}`);
  }
  assert.deepEqual(block.required, ["blockKind"]);
});
