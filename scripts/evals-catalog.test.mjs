// Gates the descriptor -> model-manifest projection in `evals/lib/catalog.mjs`.
//
// The eval suite itself is opt-in — it needs ~45 GB of models and takes tens of
// minutes — but the PROJECTION is pure: config and schemas in, tool definitions
// out, no runtime involved. It belongs in the gated suite even though the evals do
// not, because a silent defect here does not fail a run. It corrupts every number
// the run produces, and the corrupted numbers get written down as findings.
//
// That is not hypothetical. `sanitiseSchema` stripped `title` at every depth,
// including where `title` is a PROPERTY NAME, so `note.capture` and
// `calendar.createEvent` were handed to the model requiring a field the manifest
// never defined. The resulting failure was recorded as a model failure and cited as
// evidence for grammar-constrained decoding.

import test from "node:test";
import assert from "node:assert/strict";
import { loadCatalog, buildManifest, selectTools, ALLOWLISTS } from "../evals/lib/catalog.mjs";

const MODES = ["rich", "purpose"];
const catalog = loadCatalog();

/// Keywords whose value maps author-chosen names to subschemas. Mirrors the set in
/// `catalog.mjs`; the walker has to make the same distinction the projection does,
/// or it inspects a map of property names as though it were a schema.
const SCHEMA_MAP_KEYWORDS = new Set(["properties", "$defs", "definitions", "patternProperties"]);

/// Walks every genuine subschema, yielding `[pointer, schema]`. Maps of property
/// names are traversed but never yielded — they are addressing, not shape.
function* subschemas(schema, pointer = "/") {
  if (schema === null || typeof schema !== "object" || Array.isArray(schema)) return;
  yield [pointer, schema];

  for (const [key, value] of Object.entries(schema)) {
    if (value === null || typeof value !== "object") continue;

    if (SCHEMA_MAP_KEYWORDS.has(key) && !Array.isArray(value)) {
      for (const [name, subschema] of Object.entries(value)) {
        yield* subschemas(subschema, `${pointer}${key}/${name}/`);
      }
      continue;
    }

    if (Array.isArray(value)) {
      for (const [index, item] of value.entries()) yield* subschemas(item, `${pointer}${key}/${index}/`);
      continue;
    }

    yield* subschemas(value, `${pointer}${key}/`);
  }
}

test("every required property is actually defined in the projected manifest", () => {
  const undefinedRequirements = [];

  for (const mode of MODES) {
    for (const tool of buildManifest(catalog, { descriptions: mode })) {
      for (const [pointer, schema] of subschemas(tool.function.parameters)) {
        if (!Array.isArray(schema.required)) continue;
        const properties = schema.properties ?? {};
        for (const name of schema.required) {
          if (!(name in properties)) {
            undefinedRequirements.push(`${mode} ${tool.function.name} ${pointer} requires "${name}"`);
          }
        }
      }
    }
  }

  assert.deepEqual(
    undefinedRequirements,
    [],
    "A manifest that requires a property it never defines cannot be satisfied by any model, " +
      "and under grammar-constrained decoding it is an unsatisfiable grammar."
  );
});

test("a property whose name collides with a stripped keyword survives projection", () => {
  // The two real instances. Named explicitly so the regression has a witness even if
  // the generic invariant above is ever weakened.
  const expected = {
    "note.capture": ["title", "body", "kind"],
    "calendar.createevent": ["title", "startsAt", "endsAt"],
  };

  for (const mode of MODES) {
    const manifest = buildManifest(catalog, { descriptions: mode });
    for (const [toolId, required] of Object.entries(expected)) {
      const tool = manifest.find((entry) => entry.function.name === toolId);
      assert.ok(tool, `${toolId} is missing from the manifest`);
      for (const name of required) {
        assert.ok(
          name in tool.function.parameters.properties,
          `${mode}: ${toolId} lost its "${name}" property in projection`
        );
      }
    }
  }
});

test("document keywords are still stripped at schema position", () => {
  for (const mode of MODES) {
    for (const tool of buildManifest(catalog, { descriptions: mode })) {
      for (const [pointer, schema] of subschemas(tool.function.parameters)) {
        for (const keyword of ["$schema", "$id", "title"]) {
          assert.ok(
            !(keyword in schema),
            `${mode}: ${tool.function.name} leaked ${keyword} at ${pointer}`
          );
        }
      }
    }
  }
});

test("purpose mode drops descriptions without dropping a property named description", () => {
  // No shipped schema has a property named `description` today, so this guards the
  // latent half of the same defect with a synthetic entry rather than waiting for a
  // schema to trip it.
  const synthetic = [
    {
      descriptor: { id: "synthetic.tool", purpose: "A synthetic tool." },
      inputSchema: {
        $schema: "https://json-schema.org/draft/2020-12/schema",
        $id: "https://cerebralhelm.local/schemas/tools/synthetic-input.schema.json",
        title: "Synthetic input",
        type: "object",
        additionalProperties: false,
        required: ["description", "title"],
        properties: {
          description: { type: "string", description: "Prose the caller supplies." },
          title: { type: "string", description: "A title the caller supplies." },
        },
      },
    },
  ];

  const [purposeMode] = buildManifest(synthetic, { descriptions: "purpose" });
  const parameters = purposeMode.function.parameters;

  assert.deepEqual(Object.keys(parameters.properties).sort(), ["description", "title"]);
  assert.ok(!("title" in parameters), "the document's own title keyword should be stripped");
  assert.ok(
    !("description" in parameters.properties.description),
    "purpose mode should drop the description KEYWORD inside the property's schema"
  );

  const [richMode] = buildManifest(synthetic, { descriptions: "rich" });
  assert.equal(
    richMode.function.parameters.properties.description.description,
    "Prose the caller supplies.",
    "rich mode should keep the description keyword"
  );
});

test("every allowlist resolves and projects", () => {
  for (const name of Object.keys(ALLOWLISTS)) {
    const tools = buildManifest(selectTools(catalog, name), { descriptions: "rich" });
    assert.ok(tools.length > 0, `allowlist "${name}" projected no tools`);
  }
});
