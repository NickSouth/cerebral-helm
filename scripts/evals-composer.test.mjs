// The composer eval's own integrity — NOT the eval itself.
//
// The gate needs models present and takes minutes, so it stays opt-in and outside this suite
// (`node evals/run-report.mjs --gate`). What runs here is everything that can go wrong WITHOUT a
// model, and the one that matters most: that the eval measures the prompt the app actually ships.
//
// That is the whole reason this file exists. The eval used to carry its own copy of the system
// prompt, which agreed with the shipped one only by hand — so the gate could pass while the app
// composed with something else entirely. A gate measuring a composer that does not exist is worse
// than no gate, because it is trusted.

import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { resolveRepositoryRoot } from "./workspace-roots.mjs";

const repositoryRoot = resolveRepositoryRoot();
const runnerPath = path.join(repositoryRoot, "evals/run-report.mjs");
const snapshotsPath = path.join(repositoryRoot, "evals/cases/report-snapshots.json");
const composerPath = path.join(repositoryRoot, "config/models/composer.json");

const runner = fs.readFileSync(runnerPath, "utf8");
const suite = JSON.parse(fs.readFileSync(snapshotsPath, "utf8"));
const composer = JSON.parse(fs.readFileSync(composerPath, "utf8"));
const composerReports = new Map(
  composer.composerReports.map((entry) => [entry.composerReportId, entry])
);

test("the eval reads the shipped prompt rather than carrying its own", () => {
  // A literal system prompt in the runner is the failure this guards: it would drift from the
  // shipped one silently, and the gate would go on passing.
  assert.match(runner, /loadComposerConfig/);
  assert.match(runner, /composer\.json/);
  assert.equal(
    runner.includes("const SYSTEM_PROMPT ="),
    false,
    "run-report.mjs must not define its own system prompt — read config/models/composer.json"
  );
});

test("the eval validates against the real report contract, not a copy of it", () => {
  // Same argument one level down: the document the renderer consumes is the only thing worth
  // validating against.
  assert.match(runner, /schemas\/reports\/report-document\.schema\.json/);
});

test("every gated snapshot names a report the app actually composes", () => {
  // A snapshot with no composer entry is aspirational and is skipped under `--gate`. One that is
  // NOT skipped must correspond to something that ships, or the verdict is about nothing.
  const gated = suite.snapshots.filter((snapshot) => composerReports.has(snapshot.reportId));
  assert.ok(gated.length > 0, "no snapshot exercises a shipping composer");

  for (const snapshot of gated) {
    assert.ok(
      snapshot.snapshot && typeof snapshot.snapshot === "object",
      `${snapshot.id}: needs a snapshot object`
    );
    assert.ok(
      Array.isArray(snapshot.mustMention) && snapshot.mustMention.length > 0,
      `${snapshot.id}: needs at least one fact that must survive composition`
    );
  }
});

test("an aspirational snapshot carries its own instruction and says why", () => {
  // It cannot borrow the shipping prompt — there is no entry for it — so it must supply one, and it
  // must be labelled, or a reader would take a skipped case for a passing one.
  for (const snapshot of suite.snapshots) {
    if (composerReports.has(snapshot.reportId)) continue;
    assert.ok(
      typeof snapshot.instruction === "string" && snapshot.instruction.length > 0,
      `${snapshot.id}: an aspirational snapshot must carry its own instruction`
    );
    assert.ok(
      typeof snapshot.$aspirational === "string",
      `${snapshot.id}: label why this report does not ship`
    );
  }
});

test("the daily-brief snapshots mirror the shape the assembler actually produces", () => {
  // A gate fed an imagined snapshot measures an imagined composer. These keys are the sections
  // `DailyBriefAssembler` emits; a section added there without a fixture here means the gate stops
  // covering it.
  const required = ["now", "dayOfWeek", "weather", "calendar", "mail", "sprint", "profile"];

  for (const snapshot of suite.snapshots) {
    if (snapshot.reportId !== "daily-brief") continue;
    for (const key of required) {
      assert.ok(
        key in snapshot.snapshot,
        `${snapshot.id}: missing "${key}" — the assembler emits it, so the gate must exercise it`
      );
    }
    // Every source states whether it could be read. Without this the model cannot tell "nothing
    // scheduled" from "nobody could look", and it will confidently report the wrong one.
    for (const key of ["weather", "calendar", "mail", "sprint", "profile"]) {
      assert.ok(
        typeof snapshot.snapshot[key].state === "string",
        `${snapshot.id}: "${key}" must carry a state`
      );
    }
  }
});

test("at least one snapshot exercises a source that could not be read", () => {
  // The honesty case. A composer that renders an unreadable calendar as an empty one is telling the
  // reader something false in the most reassuring possible way, and nothing else in the suite would
  // catch it.
  const withUnavailable = suite.snapshots.filter((snapshot) =>
    Object.values(snapshot.snapshot ?? {}).some(
      (section) => section && typeof section === "object" && section.state === "unavailable"
    )
  );
  assert.ok(withUnavailable.length > 0, "no snapshot exercises an unavailable source");
});

test("the gate's structural thresholds are zero, and it can actually fail", () => {
  // `leafType` and `unparseable` are structural: a document that will not validate or will not parse
  // cannot be rendered, and there is no partial credit for one that sometimes can. A gate whose
  // limits drifted above zero would be reporting a broken dashboard as a pass.
  assert.match(runner, /maxLeafTypeViolations:\s*0/);
  assert.match(runner, /maxUnparseable:\s*0/);
  // A verdict with no non-zero exit is a printout, not a gate.
  assert.match(runner, /process\.exitCode = 1/);
});

test("a gating run enforces a repetition floor above one", () => {
  // Composition runs at a non-zero temperature — one sample flipped a leaf-type violation on and off
  // and briefly read as a decisive result. A verdict from a single run is a coin toss with a pass
  // rate printed next to it.
  const floor = runner.match(/minReps:\s*(\d+)/);
  assert.ok(floor, "the gate must declare a repetition floor");
  assert.ok(Number(floor[1]) > 1, "one repetition cannot decide a non-deterministic composition");
});

test("the eval applies the host's greeting filter before grading", () => {
  // The daily brief renders its own greeting, date and weather, and ASKS the model for a greeting
  // only so the host can discard it. An eval that graded the raw output would grade a document the
  // reader never sees — the same class of mistake as carrying a private copy of the prompt.
  const brief = composerReports.get("daily-brief");
  assert.equal(brief.composerDiscardsGreeting, true);
  assert.match(runner, /composerDiscardsGreeting/);
  assert.match(runner, /blockKind !== "greeting"/);
});

test("the gate is not wired into the default test run", () => {
  // It needs ~45 GB of local models and takes minutes. Opt-in, deliberately (NIC-255).
  const suiteRunner = fs.readFileSync(path.join(repositoryRoot, "scripts/test.mjs"), "utf8");
  assert.equal(suiteRunner.includes("run-report.mjs"), false);
});
