// Descriptor catalog loading and the descriptor -> model-manifest projection.
//
// The projection is the whole point of this harness: per ADR-003 the rich tool
// descriptor is authoritative, so a model-facing tool definition must be DERIVED
// from it, never hand-maintained alongside it. Everything below reads the real
// files under `config/tools/descriptors/` and `packages/contracts/schemas/` — if
// a descriptor changes, the manifest the model sees changes with it.
//
// PROTOTYPE NOTICE: this projection is deliberately a throwaway. Phase 2 of
// docs/llm-integration/PLAN.md builds the real one in Swift, next to the tool
// registry. This exists to settle the *design* questions cheaply (how much
// description a local model needs, how manifest size affects accuracy) before
// any of it is committed to in Swift. When the Swift projection lands, this file
// should be replaced by a call out to it rather than kept in sync by hand.

import { readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";

const REPO_ROOT = new URL("../../", import.meta.url).pathname;
const DESCRIPTOR_DIR = join(REPO_ROOT, "config/tools/descriptors");
const SCHEMA_ROOT = join(REPO_ROOT, "packages/contracts/schemas");

/// Maps a descriptor's `inputSchema.schemaId` to the file backing it.
///
/// Ids are `https://cerebralhelm.local/schemas/<path>`, and the repo mirrors that
/// path under `packages/contracts/schemas/`. Resolving by convention rather than a
/// lookup table means a new tool needs no registration here.
function schemaPathFor(schemaId) {
  const marker = "/schemas/";
  const index = schemaId.indexOf(marker);
  if (index === -1) throw new Error(`Unrecognised schema id: ${schemaId}`);
  return join(SCHEMA_ROOT, schemaId.slice(index + marker.length));
}

/// Every descriptor, with its input schema resolved and inlined.
export function loadCatalog() {
  return readdirSync(DESCRIPTOR_DIR)
    .filter((name) => name.endsWith(".json"))
    .map((name) => {
      const descriptor = JSON.parse(readFileSync(join(DESCRIPTOR_DIR, name), "utf8"));
      const inputSchema = JSON.parse(
        readFileSync(schemaPathFor(descriptor.inputSchema.schemaId), "utf8")
      );
      return { descriptor, inputSchema };
    })
    .sort((a, b) => a.descriptor.id.localeCompare(b.descriptor.id));
}

/// JSON Schema keywords that describe the document rather than the shape.
///
/// They cost prompt tokens and some runtimes reject them outright.
const META_KEYWORDS = new Set(["$schema", "$id", "title"]);

/// Keywords whose value is a MAP from author-chosen names to subschemas.
///
/// The distinction is load-bearing, not pedantry. Inside one of these the keys are
/// PROPERTY NAMES, not keywords, and filtering them by keyword deletes real fields:
/// stripping `title` at every depth removed the required `title` property from both
/// `note.capture` and `calendar.createEvent`, so the manifest required a field it
/// never defined and no model could satisfy it. That was mistaken for a model
/// failure and cited as evidence for grammar-constrained decoding. `description`
/// under `--descriptions=purpose` is the same bug waiting for a schema to trip it.
const SCHEMA_MAP_KEYWORDS = new Set(["properties", "$defs", "definitions", "patternProperties"]);

/// Strips the JSON Schema keywords a tool-calling API rejects or ignores.
///
/// `description` is kept in `rich` mode: it is load-bearing for a local model
/// choosing between four near-identical browser-opening tools.
function sanitiseSchema(schema, { keepDescriptions }) {
  if (schema === null || typeof schema !== "object") return schema;
  if (Array.isArray(schema)) return schema.map((item) => sanitiseSchema(item, { keepDescriptions }));

  const out = {};
  for (const [key, value] of Object.entries(schema)) {
    if (META_KEYWORDS.has(key)) continue;
    if (key === "description" && !keepDescriptions) continue;

    if (SCHEMA_MAP_KEYWORDS.has(key) && value !== null && typeof value === "object" && !Array.isArray(value)) {
      // Recurse into each subschema; never keyword-filter the name that addresses it.
      out[key] = Object.fromEntries(
        Object.entries(value).map(([name, subschema]) => [
          name,
          sanitiseSchema(subschema, { keepDescriptions }),
        ])
      );
      continue;
    }

    out[key] = sanitiseSchema(value, { keepDescriptions });
  }
  return out;
}

/// Builds the tool description the model reads.
///
/// Two modes, because which one a local model needs is an open question
/// (docs/llm-integration/PLAN.md, open decision 2):
///
/// - `purpose`: the descriptor's one-line `purpose` alone — what exists today.
/// - `rich`:    `purpose` plus the input schema's own prose description.
///
/// If `rich` measurably beats `purpose`, the descriptor contract needs a
/// model-facing description field and the plan's open decision is settled by
/// evidence rather than taste.
function describe({ descriptor, inputSchema }, mode) {
  if (mode === "purpose") return descriptor.purpose;
  const detail = inputSchema.description;
  return detail ? `${descriptor.purpose}\n\n${detail}` : descriptor.purpose;
}

/// Projects catalog entries into OpenAI-style tool definitions.
///
/// Risk and confirmation policy are deliberately ABSENT from what the model sees.
/// The model's job is to choose an action; whether that action needs confirming is
/// decided afterwards by the deterministic policy engine, from the descriptor.
/// Telling the model an action is "destructive" would invite it to reason about
/// its own permissions, which is precisely the decision that does not belong to it.
export function buildManifest(entries, { descriptions = "rich" } = {}) {
  return entries.map((entry) => ({
    type: "function",
    function: {
      name: entry.descriptor.id,
      description: describe(entry, descriptions),
      parameters: sanitiseSchema(entry.inputSchema, {
        keepDescriptions: descriptions === "rich",
      }),
    },
  }));
}

/// Named tool allowlists, standing in for the phase-4 scoped agents.
///
/// The architectural claim under test is that a narrow allowlist beats a wide one
/// for a local model — so these are sized like real agent surfaces, and `all` is
/// the Heimlich case that should degrade most.
export const ALLOWLISTS = {
  // Deliberately tiny: the floor for how well selection can possibly work.
  minimal: ["note.capture", "note.search", "system.status.read"],

  // A plausible "Project Manager" surface.
  project: [
    "project.open",
    "project.scaffold",
    "git.clone",
    "linear.createissue",
    "note.capture",
    "note.search",
    "note.read",
  ],

  // A plausible "day planning" surface — includes the four confusable
  // browser-opening tools on purpose.
  daily: [
    "calendar.createevent",
    "mail.open",
    "messages.send",
    "google.search",
    "web.open",
    "url.open",
    "youtube.search",
    "system.status.read",
  ],

  // Knowledge work — five note tools whose names differ by one verb.
  knowledge: ["note.capture", "note.read", "note.list", "note.search", "note.open", "course.list", "course.note.create"],

  // Everything. The Heimlich case.
  all: null,
};

/// Resolves an allowlist name to catalog entries, preserving catalog order.
export function selectTools(catalog, allowlistName) {
  const ids = ALLOWLISTS[allowlistName];
  if (ids === undefined) throw new Error(`Unknown allowlist: ${allowlistName}`);
  if (ids === null) return catalog;

  const wanted = new Set(ids);
  const selected = catalog.filter((entry) => wanted.has(entry.descriptor.id));
  const missing = [...wanted].filter(
    (id) => !selected.some((entry) => entry.descriptor.id === id)
  );
  if (missing.length) {
    throw new Error(`Allowlist "${allowlistName}" names unknown tools: ${missing.join(", ")}`);
  }
  return selected;
}
