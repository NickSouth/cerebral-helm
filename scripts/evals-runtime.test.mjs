// Gates the pure half of the eval harness's runtime adapters.
//
// Only the transcript translation is covered — everything else in `runtime.mjs`
// needs a live runtime and belongs to the opt-in suite. This part is worth gating
// because its failure mode is disguised: `lib/conversation.mjs` appends tool results
// in Ollama's shape (`{role, name, content}`), and if the OpenAI adapter fails to
// re-key them by `tool_call_id`, the server cannot correlate a result with its call
// and the model re-issues it. That surfaces as `runaway` in the scoring — a verdict
// about the MODEL — when the cause is the harness. This repo has already recorded
// one harness defect as a model failure; once is enough.

import test from "node:test";
import assert from "node:assert/strict";
import { toOpenAITurns, RUNTIMES } from "../evals/lib/runtime.mjs";

test("every runtime exposes the same seam", () => {
  for (const [id, runtime] of Object.entries(RUNTIMES)) {
    assert.equal(runtime.id, id, `${id} disagrees with its own key`);
    // `compose` is as load-bearing as `chat`: the composer is the surface where the
    // runtimes measurably differ, so a runtime that only implements half the seam
    // would silently drop out of the comparison it exists to be part of.
    for (const member of ["chat", "compose", "unload", "ready"]) {
      assert.equal(typeof runtime[member], "function", `${id} is missing ${member}()`);
    }
  }
});

test("both runtimes are registered", () => {
  assert.deepEqual(Object.keys(RUNTIMES).sort(), ["llamacpp", "ollama"]);
});

test("a tool result is re-keyed to the id of the call it answers", () => {
  const translated = toOpenAITurns([
    { role: "system", content: "sys" },
    { role: "user", content: "find my notes" },
    {
      role: "assistant",
      content: "",
      tool_calls: [{ id: "call_abc", type: "function", function: { name: "note.search" } }],
    },
    // Ollama's shape, as `lib/conversation.mjs` appends it.
    { role: "tool", name: "note.search", content: '{"results":[]}' },
  ]);

  const toolTurn = translated.at(-1);
  assert.equal(toolTurn.tool_call_id, "call_abc");
  assert.equal(toolTurn.content, '{"results":[]}');
  assert.ok(!("name" in toolTurn), "the Ollama-only `name` key should not survive translation");
});

test("results are matched per tool across a multi-call turn", () => {
  const translated = toOpenAITurns([
    {
      role: "assistant",
      content: "",
      tool_calls: [
        { id: "call_1", function: { name: "note.search" } },
        { id: "call_2", function: { name: "note.read" } },
      ],
    },
    { role: "tool", name: "note.read", content: "second" },
    { role: "tool", name: "note.search", content: "first" },
  ]);

  assert.equal(translated[1].tool_call_id, "call_2", "matched by name, not by position");
  assert.equal(translated[2].tool_call_id, "call_1");
});

test("an already-OpenAI-shaped tool turn is left alone", () => {
  const [turn] = toOpenAITurns([{ role: "tool", tool_call_id: "call_x", content: "done" }]);
  assert.equal(turn.tool_call_id, "call_x");
});

test("an uncorrelatable result is passed through rather than dropped", () => {
  // Dropping it would be worse than passing it through: the model would never learn
  // what its call returned, and would reasonably call again.
  const [turn] = toOpenAITurns([{ role: "tool", name: "note.search", content: "orphan" }]);
  assert.equal(turn.content, "orphan");
  assert.equal(turn.tool_call_id, undefined);
});

test("non-tool turns are untouched", () => {
  const input = [
    { role: "system", content: "sys" },
    { role: "user", content: "hi" },
    { role: "assistant", content: "hello" },
  ];
  assert.deepEqual(toOpenAITurns(input), input);
});
