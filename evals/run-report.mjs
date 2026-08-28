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

const COMPOSER_CONFIG_PATH = new URL("../config/models/composer.json", import.meta.url);

/**
 * The SHIPPING composer configuration — the prompt and budget the app actually uses.
 *
 * Read from `config/models/composer.json` rather than restated here, and that is the whole point of
 * this file as a gate: an eval that measures a prompt of its own measures a composer that does not
 * exist. Before this, the two were separate constants that agreed only by hand.
 */
function loadComposerConfig() {
  const config = JSON.parse(readFileSync(COMPOSER_CONFIG_PATH, "utf8"));
  const byReport = new Map(
    (config.composerReports ?? []).map((entry) => [entry.composerReportId, entry])
  );
  return { systemPrompt: config.composerSystemPrompt, byReport };
}

/**
 * The bar a composer change has to clear, as absolute numbers (owner decision).
 *
 * Absolute rather than relative to a recorded baseline: simpler to reason about, and a baseline that
 * drifts down one point per change is how a gate stops meaning anything. Set against what has
 * actually been measured rather than what would be nice — Ollama produced a schema-invalid document
 * on 6 of 18 runs of one snapshot before the report schema was bounded, and 0 of 18 after.
 *
 * `leafType` and `unparseable` are ZERO because both are structural: a document that will not
 * validate or will not parse cannot be rendered, and there is no partial credit for one that
 * sometimes can. `pass` allows for `dropped_facts`, which is a judgement failure rather than a
 * structural one and which no grammar can prevent.
 */
const GATE = {
  minPassRate: 0.8,
  maxLeafTypeViolations: 0,
  maxUnparseable: 0,
  maxDroppedFactRate: 0.2,
  /** Composition runs at a non-zero temperature, so one sample decides nothing. */
  minReps: 3
};

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
    // `--gate` turns this from a look into a verdict: thresholds are applied and the process exits
    // non-zero on a breach. "Swap the model" is a design goal, and a swap without a regression gate
    // is a hope.
    gate: null,
  };
  for (const arg of argv) {
    const [key, value] = arg.replace(/^--/, "").split("=");
    if (key in options) options[key] = value === undefined ? "true" : value;
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

/**
 * Whether what SURVIVES the greeting filter still restates the deterministic header.
 *
 * Run against the kept document, not the raw output: the model is asked for a greeting and the host
 * throws it away, so flagging that block would flag the thing that was requested. What matters is a
 * SECOND restatement — a `line` or `metric` repeating the day and the weather after the greeting has
 * already been discarded — which is the duplication a reader would actually see.
 *
 * Reported as REVIEW rather than as a failure: it is a judgement about prose, the document is
 * perfectly valid, and a gate that failed on wording would be a gate nobody could keep green.
 */
function restatesHeader(document, snapshot) {
  const first = (document.blocks ?? [])[0];
  if (!first) return null;
  const text = `${first.text ?? ""} ${first.label ?? ""} ${first.value ?? ""}`.toLowerCase();
  const echoes = [];
  const weekday = snapshot.dayOfWeek?.toLowerCase();
  if (weekday && text.includes(weekday)) echoes.push(snapshot.dayOfWeek);
  const condition = snapshot.weather?.condition?.toLowerCase();
  if (condition && text.includes(condition)) echoes.push(snapshot.weather.condition);
  const temperature = snapshot.weather?.temperatureF;
  if (temperature !== undefined && text.includes(String(temperature))) {
    echoes.push(`${temperature}°F`);
  }
  return echoes.length ? echoes : null;
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

/// The snapshot as the model receives it — assembled exactly as `ReportComposer.userContent` does.
///
/// `instruction` comes from the shipping composer config when the report has an entry, and from the
/// fixture only for an ASPIRATIONAL case describing a surface that does not exist yet. A gate must
/// not grade a prompt nobody ships.
function userContent(snapshot, instruction) {
  return (
    `reportId: ${snapshot.reportId}\n\n${instruction}\n\n` +
    `SNAPSHOT:\n${JSON.stringify(snapshot.snapshot, null, 2)}`
  );
}

async function compose({ runtime, model, snapshot, instruction, systemPrompt, formatMode, schema, think, maxOutputTokens }) {
  return RUNTIMES[runtime].compose({
    model,
    system: systemPrompt,
    user: userContent(snapshot, instruction),
    responseSchema: schema,
    formatMode,
    think,
    maxOutputTokens,
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
  const composer = loadComposerConfig();
  let snapshots = suite.snapshots;
  if (options.snapshot) snapshots = snapshots.filter((s) => s.id === options.snapshot);
  if (!snapshots.length) throw new Error("No snapshots matched.");

  await assertRuntimeReady(options.runtime, options.model);

  const gating = options.gate !== null && options.gate !== "false";
  // Under `--gate` the repetition floor is enforced rather than suggested: composition runs at a
  // non-zero temperature, and a verdict from one sample is a coin toss with a pass rate printed
  // next to it.
  const reps = gating
    ? Math.max(GATE.minReps, Number(options.reps) || 0)
    : Math.max(1, Number(options.reps) || 1);
  console.log(
    `${snapshots.length} snapshots · ${options.runtime} · ${options.model} · ` +
      `format=${options.format} · think=${options.think} · ${reps} rep${reps === 1 ? "" : "s"}\n`
  );

  // A gate grades only what ships. An ASPIRATIONAL fixture describes a surface with no composer
  // entry — worth keeping as a look at where the format is going, worth nothing as a verdict — so it
  // is dropped from a gating run and named rather than silently skipped.
  if (gating) {
    const aspirational = snapshots.filter((snapshot) => !composer.byReport.has(snapshot.reportId));
    if (aspirational.length) {
      console.log(
        `${DIM}gate: skipping ${aspirational.length} aspirational snapshot(s) with no composer ` +
          `entry — ${aspirational.map((s) => s.id).join(", ")}${RESET}`
      );
    }
    snapshots = snapshots.filter((snapshot) => composer.byReport.has(snapshot.reportId));
    if (!snapshots.length) throw new Error("No shipping snapshots to gate.");
  }

  const rows = [];
  // Repetitions are the OUTER loop so a run reads as successive passes over the same
  // suite rather than the same snapshot several times in a row. Composer results vary
  // at temperature 0.4; the summary reports the rate, not the last sample.
  for (let rep = 0; rep < reps; rep += 1) {
    if (reps > 1) console.log(`${BOLD}── rep ${rep + 1}/${reps}${RESET}`);
  for (const snapshot of snapshots) {
    process.stdout.write(`${BOLD}── ${snapshot.id}${RESET}\n`);

    const entry = composer.byReport.get(snapshot.reportId);
    let result;
    try {
      result = await compose({
        runtime: options.runtime,
        model: options.model,
        snapshot,
        // The shipping prompt, or the fixture's own for an aspirational surface.
        systemPrompt: composer.systemPrompt,
        instruction: entry?.composerInstruction ?? snapshot.instruction,
        maxOutputTokens: entry?.composerMaxOutputTokens,
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
      const blocks = JSON.parse(cleaned).blocks;
      // The host discards the blocks a report writes itself — the daily brief renders its greeting,
      // date and weather deterministically and ASKS the model for a greeting only so it can be
      // thrown away. Applying the same filter here is not a detail: an eval that graded the raw
      // output would be grading a document the reader never sees, which is the failure this whole
      // file exists to prevent.
      const kept = entry?.composerDiscardsGreeting
        ? blocks.filter((block) => block?.blockKind !== "greeting")
        : blocks;
      // The system supplies the envelope — exactly as the real Composer does.
      document = { schemaVersion: "1.0.0", reportId: snapshot.reportId, blocks: kept };
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
    const restated = document ? restatesHeader(document, snapshot.snapshot) : null;

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
    if (restated) {
      console.log(
        `  ${YELLOW}REVIEW — opens by restating the deterministic header: ${restated.join(", ")}${RESET}`
      );
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
      restatesHeader: restated ?? undefined,
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
  const restating = rows.filter((row) => row.restatesHeader).length;
  if (restating) {
    console.log(
      `${YELLOW}header restated: ${restating}/${rows.length}${RESET} ` +
        `${DIM}(prose, not validity — the model is spending its first block on what is already on screen)${RESET}`
    );
  }
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

  if (gating) {
    // Leave the machine as we found it before the verdict, so a failing gate does not also leave a
    // 21 GB model resident.
    await RUNTIMES[options.runtime].unload?.(options.model);
    reportGate(rows);
  }

  // Leave the machine as we found it. A no-op on llama.cpp, where the memory is the
  // process — stopping the server is the operator's job, not the harness's.
  await RUNTIMES[options.runtime].unload?.(options.model);
}

/**
 * Applies the thresholds and exits non-zero on a breach.
 *
 * Every breach is printed, not just the first: a composer change that broke two things should not
 * need two runs to discover, and each run costs minutes.
 */
function reportGate(rows) {
  const total = rows.length;
  const passed = rows.filter((row) => row.outcome === "pass").length;
  const leafType = rows.filter((row) => row.leafTypeErrors?.length).length;
  const unparseable = rows.filter((row) => row.outcome === "unparseable").length;
  const dropped = rows.filter((row) => row.outcome === "dropped_facts").length;
  const errored = rows.filter((row) => row.outcome === "error").length;

  const breaches = [];
  const passRate = total ? passed / total : 0;
  const droppedRate = total ? dropped / total : 0;

  if (passRate < GATE.minPassRate) {
    breaches.push(
      `pass rate ${(passRate * 100).toFixed(1)}% is below the required ${(GATE.minPassRate * 100).toFixed(0)}%`
    );
  }
  if (leafType > GATE.maxLeafTypeViolations) {
    breaches.push(
      `${leafType} leaf-type violation(s); the limit is ${GATE.maxLeafTypeViolations}. A document that will not validate cannot be rendered.`
    );
  }
  if (unparseable > GATE.maxUnparseable) {
    breaches.push(
      `${unparseable} unparseable document(s); the limit is ${GATE.maxUnparseable}. Truncation is not invalidity — check the output cap.`
    );
  }
  if (droppedRate > GATE.maxDroppedFactRate) {
    breaches.push(
      `${(droppedRate * 100).toFixed(1)}% of compositions dropped a required fact; the limit is ${(GATE.maxDroppedFactRate * 100).toFixed(0)}%`
    );
  }
  if (errored > 0) {
    breaches.push(`${errored} composition(s) errored outright`);
  }

  console.log(`${"=".repeat(60)}`);
  if (breaches.length === 0) {
    console.log(`GATE PASSED  ${passed}/${total} clean · 0 leaf-type · 0 unparseable`);
    return;
  }
  console.log(`${YELLOW}GATE FAILED${RESET}`);
  for (const breach of breaches) console.log(`  - ${breach}`);
  console.log(
    `\n${DIM}Composition is not deterministic: re-run before concluding a change caused this, ` +
      `and read the per-snapshot output above for which case moved.${RESET}`
  );
  process.exitCode = 1;
}

main().catch((error) => {
  console.error(`error: ${error.message}`);
  process.exit(1);
});
