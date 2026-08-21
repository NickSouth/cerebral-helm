#!/usr/bin/env node
// Passive-tier composer eval — docs/llm-integration/PLAN.md phase 1.
//
// Phase 1 replaces the deterministic Composer with a model, keeping the same input
// type and the same output type. This measures whether a local model can actually
// hold up that contract:
//
//   1. Does it emit a SCHEMA-VALID ReportDocument? Checked with ajv against the real
//      packages/contracts/schemas/reports/report-document.schema.json — the same
//      document the renderer consumes.
//   2. Does it FABRICATE? A brief that invents a meeting is worse than no brief, so
//      every number in the output is traced back to the snapshot.
//   3. Is it fast enough to sit on a dashboard?
//   4. Is the prose any good? Not automatable — printed for a human to judge.
//
// `--format=schema` uses the runtime's structured-output mode; `--format=none` asks
// for JSON in the prompt and parses whatever comes back. `--runtime` chooses who
// serves it, and that pairing is what settled the grammar question: with the SAME
// schema supplied, Ollama produced a schema-invalid document on 6 of 6 runs of one
// snapshot and llama.cpp on 0 of 6, because only the latter compiles the schema to a
// grammar. Ollama's constrained mode scored no better than its unconstrained one.
//
// Which is why `leaf-type violations` is reported on its own line: it is the number
// the runtime question turns on, and an aggregate pass rate buries it among dropped
// facts. Use `--reps` — temperature is 0.4 here and one sample decides nothing.

import { readFileSync, writeFileSync } from "node:fs";
import Ajv2020 from "ajv/dist/2020.js";
import { RUNTIMES, assertRuntimeReady } from "./lib/runtime.mjs";

const SCHEMA_PATH = new URL(
  "../packages/contracts/schemas/reports/report-document.schema.json",
  import.meta.url
);

const DIM = "\x1b[2m";
const BOLD = "\x1b[1m";
const YELLOW = "\x1b[33m";
const RESET = "\x1b[0m";

const SYSTEM_PROMPT = `You compose CerebralHelm report documents.

You are given a SNAPSHOT of typed data that was gathered deterministically. Your only job is to turn it into the BLOCKS of a report document. The envelope around them is set by the system, not by you.

Absolute rules:
- Use ONLY facts present in the snapshot. Never invent an event, number, name, or status. If the snapshot is empty, say so plainly — do not pad the report with filler.
- Do not restate the snapshot mechanically. Lead with what matters, and be brief. This is read at a glance.
- Times in the snapshot are local wall-clock. Render them the way a person would say them.

Block kinds available: greeting, line, metric, list, checklist, empty, count, proposal.
Each block needs "blockKind". greeting/line/empty use "text"; greeting may set "greetingSize" (hero|standard); line may set "lineEmphasis" (normal|strong|muted). metric uses "label", "value", and may set "metricTone" (neutral|positive|warning|critical). count uses "value" and "label". list uses "listItems", an array of objects each with "text" and optionally "meta".

Reply with a JSON object containing ONLY a "blocks" array, and nothing else.`;

/// Inlines internal $refs so the schema can be handed to a structured-output API.
/// Runtimes vary in $ref support and a silently ignored $ref would mean the output is
/// unconstrained while appearing constrained — worse than not using the mode at all.
function inlineRefs(node, root, seen = new Set()) {
  if (node === null || typeof node !== "object") return node;
  if (Array.isArray(node)) return node.map((item) => inlineRefs(item, root, seen));

  if (typeof node.$ref === "string" && node.$ref.startsWith("#/")) {
    const key = node.$ref;
    if (seen.has(key)) return {};
    const target = node.$ref
      .slice(2)
      .split("/")
      .reduce((acc, part) => acc?.[part.replace(/~1/g, "/").replace(/~0/g, "~")], root);
    return inlineRefs(target, root, new Set([...seen, key]));
  }

  const out = {};
  for (const [key, value] of Object.entries(node)) {
    if (key === "$defs" || key === "$schema" || key === "$id") continue;
    out[key] = inlineRefs(value, root, seen);
  }
  return out;
}

function parseArgs(argv) {
  // `think` defaults OFF. Qwen3.6 is a hybrid-reasoning model and left to itself
  // spends thousands of tokens deliberating before emitting the document — measured
  // at 80–130s per report, which is unusable on a dashboard. Composition from an
  // already-typed snapshot is not a reasoning task; it is a rendering task.
  //
  // `reps` defaults to 1 for a quick look, but a single composition proves nothing:
  // temperature is 0.4 here, unlike the tool suites which pin it to 0. One sample once
  // showed a leaf-type violation appearing and vanishing between runs and briefly read
  // as a decisive result; six repetitions gave the real rates. Use `--reps` before
  // drawing any conclusion.
  const options = {
    runtime: "ollama",
    model: "qwen3.6:35b-mlx",
    format: "schema",
    snapshot: null,
    json: null,
    think: "false",
    reps: "1",
  };
  for (const arg of argv) {
    const [key, value] = arg.replace(/^--/, "").split("=");
    if (key in options) options[key] = value;
    else throw new Error(`Unknown option: ${arg}`);
  }
  if (!(options.runtime in RUNTIMES)) {
    throw new Error(
      `Unknown runtime "${options.runtime}". Known: ${Object.keys(RUNTIMES).join(", ")}`
    );
  }
  return options;
}

/// Every number appearing anywhere in the snapshot, as strings.
///
/// Used to trace figures in the output back to a source. Times contribute both their
/// 24-hour and 12-hour forms, since "09:30" is legitimately rendered "9:30".
function sourceNumbers(value, acc = new Set()) {
  if (value === null || value === undefined) return acc;
  if (typeof value === "number") {
    acc.add(String(value));
    return acc;
  }
  if (typeof value === "string") {
    for (const match of value.matchAll(/\d+/g)) {
      acc.add(match[0]);
      acc.add(String(Number(match[0])));
      const hour = Number(match[0]);
      if (hour > 12 && hour <= 23) acc.add(String(hour - 12));
    }
    return acc;
  }
  if (typeof value === "object") {
    for (const item of Object.values(value)) sourceNumbers(item, acc);
  }
  return acc;
}

/// Numbers in the composed prose with no counterpart in the snapshot.
///
/// Reported as REVIEW rather than failure: a model may legitimately derive a figure
/// ("2 meetings" from a two-item array). A flagged number is a prompt to look, not a
/// verdict — but an unexplained proper number is the signature of fabrication.
function unsourcedNumbers(document, snapshot) {
  const allowed = sourceNumbers(snapshot);
  // Small integers are almost always counts the model derived correctly.
  for (let n = 0; n <= 12; n += 1) allowed.add(String(n));

  const text = JSON.stringify(document.blocks ?? []);
  const found = new Set();
  for (const match of text.matchAll(/\d+/g)) {
    if (!allowed.has(match[0])) found.add(match[0]);
  }
  return [...found];
}

function renderPreview(document) {
  const lines = [];
  for (const block of document.blocks ?? []) {
    switch (block.blockKind) {
      case "greeting":
        lines.push(`${BOLD}${block.text ?? ""}${RESET}`);
        break;
      case "line":
        lines.push(`  ${block.text ?? ""}`);
        break;
      case "metric":
        lines.push(`  ${block.label ?? ""}: ${BOLD}${block.value ?? ""}${RESET}`);
        break;
      case "count":
        lines.push(`  ${BOLD}${block.value ?? ""}${RESET} ${block.label ?? ""}`);
        break;
      case "list":
        for (const item of block.listItems ?? []) {
          lines.push(`  • ${item.text}${item.meta ? `  ${DIM}${item.meta}${RESET}` : ""}`);
        }
        break;
      case "empty":
        lines.push(`  ${DIM}${block.text ?? "(nothing)"}${RESET}`);
        break;
      default:
        lines.push(`  ${DIM}[${block.blockKind}]${RESET} ${block.text ?? ""}`);
    }
  }
  return lines.join("\n");
}

/// The snapshot as the model receives it.
function userContent(snapshot) {
  return (
    `reportId: ${snapshot.reportId}\n\n${snapshot.instruction}\n\n` +
    `SNAPSHOT:\n${JSON.stringify(snapshot.snapshot, null, 2)}`
  );
}

async function compose({ runtime, model, snapshot, formatMode, schema, think }) {
  return RUNTIMES[runtime].compose({
    model,
    system: SYSTEM_PROMPT,
    user: userContent(snapshot),
    responseSchema: schema,
    formatMode,
    think,
  });
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  const rawSchema = JSON.parse(readFileSync(SCHEMA_PATH, "utf8"));

  // The model is constrained to BLOCKS only. `schemaVersion` and `reportId` are
  // envelope fields the system already knows, and asking a model to restate them was
  // the single largest source of invalid documents in the first run — every failure
  // was a malformed `schemaVersion`, not a malformed report. Narrowing the model's
  // output to exactly what needs judgement removes that class of error entirely, and
  // is what the real Composer should do.
  const composerSchema = inlineRefs(
    {
      type: "object",
      additionalProperties: false,
      required: ["blocks"],
      properties: { blocks: rawSchema.properties.blocks },
    },
    rawSchema
  );

  const ajv = new Ajv2020({ strict: false, allErrors: true });
  const validate = ajv.compile(rawSchema);

  const suite = JSON.parse(
    readFileSync(new URL("./cases/report-snapshots.json", import.meta.url), "utf8")
  );
  let snapshots = suite.snapshots;
  if (options.snapshot) snapshots = snapshots.filter((s) => s.id === options.snapshot);
  if (!snapshots.length) throw new Error("No snapshots matched.");

  await assertRuntimeReady(options.runtime, options.model);

  const reps = Math.max(1, Number(options.reps) || 1);
  console.log(
    `${snapshots.length} snapshots · ${options.runtime} · ${options.model} · ` +
      `format=${options.format} · think=${options.think} · ${reps} rep${reps === 1 ? "" : "s"}\n`
  );

  const rows = [];
  // Repetitions are the OUTER loop so a run reads as successive passes over the same
  // suite rather than the same snapshot several times in a row. Composer results vary
  // at temperature 0.4; the summary reports the rate, not the last sample.
  for (let rep = 0; rep < reps; rep += 1) {
    if (reps > 1) console.log(`${BOLD}── rep ${rep + 1}/${reps}${RESET}`);
  for (const snapshot of snapshots) {
    process.stdout.write(`${BOLD}── ${snapshot.id}${RESET}\n`);

    let result;
    try {
      result = await compose({
        runtime: options.runtime,
        model: options.model,
        snapshot,
        formatMode: options.format,
        schema: composerSchema,
        think: options.think === "true",
      });
    } catch (error) {
      console.log(`  ${YELLOW}error: ${error.message}${RESET}\n`);
      rows.push({ id: snapshot.id, rep, outcome: "error", detail: error.message });
      continue;
    }

    let document = null;
    let parseError = null;
    try {
      // A model asked for "JSON and nothing else" still sometimes wraps it in a fence.
      const cleaned = result.text.trim().replace(/^```(?:json)?\n?/, "").replace(/```$/, "");
      // The system supplies the envelope — exactly as the real Composer will.
      document = { schemaVersion: "1.0.0", reportId: snapshot.reportId, blocks: JSON.parse(cleaned).blocks };
    } catch (error) {
      parseError = error.message;
    }

    const valid = document ? validate(document) : false;
    const schemaErrors = validate.errors ?? [];
    const missing = document
      ? (snapshot.mustMention ?? []).filter(
          (needle) => !JSON.stringify(document).toLowerCase().includes(needle.toLowerCase())
        )
      : snapshot.mustMention ?? [];
    const unsourced = document ? unsourcedNumbers(document, snapshot.snapshot) : [];

    const outcome = parseError
      ? "unparseable"
      : !valid
        ? "invalid_schema"
        : missing.length
          ? "dropped_facts"
          : "pass";

    console.log(
      `  ${outcome === "pass" ? "pass" : YELLOW + outcome + RESET}` +
        `  ${DIM}${result.wallMs}ms · ${result.outputTokens ?? "–"} tokens · ` +
        `${document?.blocks?.length ?? 0} blocks${RESET}`
    );
    if (parseError) console.log(`  ${YELLOW}parse: ${parseError}${RESET}`);
    if (!valid && !parseError && schemaErrors.length) {
      console.log(`  ${YELLOW}schema: ${schemaErrors.slice(0, 3).map((e) => `${e.instancePath || "/"} ${e.message}`).join("; ")}${RESET}`);
    }
    if (missing.length) console.log(`  ${YELLOW}dropped: ${missing.join(", ")}${RESET}`);
    if (unsourced.length) {
      console.log(`  ${YELLOW}REVIEW — numbers with no source in snapshot: ${unsourced.join(", ")}${RESET}`);
    }
    // The rendered preview exists for a human to judge the prose. Over repetitions it
    // is noise, so only a single-rep run prints it.
    if (document && reps === 1) console.log(`\n${renderPreview(document)}\n`);

    rows.push({
      id: snapshot.id,
      rep,
      outcome,
      // The specific defect the grammar question turns on: a leaf typed as string
      // arriving as a number. Recorded separately from the outcome because it is the
      // measurement, and an aggregate pass rate buries it.
      leafTypeErrors: schemaErrors.filter((e) => e.keyword === "type").map((e) => `${e.instancePath} ${e.message}`),
      wallMs: result.wallMs,
      outputTokens: result.outputTokens ?? null,
      blocks: document?.blocks?.length ?? 0,
      unsourced,
      // The raw text, but only when it could not be parsed. Same reasoning the tool
      // suite records `actualArgs`: without it an unparseable outcome has to be
      // reproduced by hand, and a rare one may not reproduce at all. Truncation, an
      // empty completion, and a fenced document are three different bugs that look
      // identical in the outcome column.
      rawText: parseError ? result.text : undefined,
      document: reps === 1 ? document : undefined,
    });
  }
  }

  const passed = rows.filter((row) => row.outcome === "pass").length;
  const leafViolations = rows.filter((row) => row.leafTypeErrors?.length).length;
  const wall = rows.map((row) => row.wallMs).filter(Boolean).sort((a, b) => a - b);
  console.log(`${"=".repeat(60)}`);
  console.log(
    `${passed}/${rows.length} composed cleanly · ${options.runtime} · format=${options.format}`
  );
  // Called out on its own line: this is the number the runtime comparison turns on,
  // and it is invisible in a pass rate that also counts dropped facts.
  console.log(
    `leaf-type violations: ${leafViolations}/${rows.length}` +
      (wall.length ? `   median ${wall[Math.floor(wall.length / 2)]}ms` : "")
  );
  if (reps > 1) {
    const byOutcome = {};
    for (const row of rows) byOutcome[row.outcome] = (byOutcome[row.outcome] ?? 0) + 1;
    console.log(
      `outcomes: ${Object.entries(byOutcome).map(([k, v]) => `${k} ${v}`).join(" · ")}`
    );
  }

  if (options.json) {
    writeFileSync(options.json, JSON.stringify({ options, rows }, null, 2));
    console.log(`wrote ${options.json}`);
  }

  // Leave the machine as we found it. A no-op on llama.cpp, where the memory is the
  // process — stopping the server is the operator's job, not the harness's.
  await RUNTIMES[options.runtime].unload?.(options.model);
}

main().catch((error) => {
  console.error(`error: ${error.message}`);
  process.exit(1);
});
