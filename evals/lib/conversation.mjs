// Multi-turn agent loop and its scoring — docs/llm-integration/PLAN.md phase 2/5.
//
// The single-turn suite asks "does it pick the right tool?". This asks the four
// questions that decide whether a local model can be Heimlich at all:
//
//   1. Does it SEQUENCE tools sensibly (search, then read, then answer)?
//   2. Does it USE what a tool returned, or ignore it and invent an answer?
//   3. Does it STOP? Knowing when to stop is the classic local-model failure,
//      and unlike quality it is objectively measurable — count the turns.
//   4. Does it admit a capability gap instead of faking it?
//
// Tools are NEVER executed. Results are stubbed per scenario, which is both safer
// (nothing touches the real calendar or knowledge vault) and stricter: a stub can
// return the empty case, the too-many-results case, or the error case on demand,
// and every run sees byte-identical results so a difference is the model's.

/// Runs one scenario to termination or to `maxTurns`.
export async function runConversation({ runtime, model, system, scenario, tools }) {
  const messages = [
    { role: "system", content: system },
    { role: "user", content: scenario.prompt },
  ];

  const calls = [];
  const timings = [];
  let finalText = null;
  let terminated = false;
  let error = null;

  for (let turn = 0; turn < (scenario.maxTurns ?? 6); turn += 1) {
    let result;
    try {
      result = await runtime.chat({ model, messages, tools });
    } catch (cause) {
      error = cause.message;
      break;
    }
    timings.push(result.timing);

    if (!result.calls.length) {
      finalText = result.text ?? "";
      terminated = true;
      break;
    }

    // Append the assistant's own message before any results, so the thread stays
    // coherent from the model's point of view.
    messages.push(result.assistantMessage ?? { role: "assistant", content: "" });

    for (const call of result.calls) {
      calls.push({ name: call.name, args: call.args ?? null, turn });
      messages.push({
        role: "tool",
        // Ollama's chat API keys tool results by name rather than a call id.
        name: call.name,
        content: JSON.stringify(stubResultFor(scenario, call.name)),
      });
    }
  }

  return { calls, finalText, terminated, error, timings };
}

/// The canned result a tool returns in this scenario.
///
/// An unstubbed tool deliberately returns a well-formed EMPTY result rather than an
/// error: a model that wandered off the expected path should be judged on how it
/// recovers, not handed an exception that would end the run for reasons of its own.
function stubResultFor(scenario, toolName) {
  const stub = (scenario.toolResults ?? {})[toolName];
  if (stub !== undefined) return stub;
  return { ok: true, results: [], note: "No data available for this tool." };
}

const OUTCOMES = [
  "runaway",
  "forbidden",
  "missing_call",
  "wrong_order",
  "redundant_call",
  "no_synthesis",
  "error",
  "pass",
];

export { OUTCOMES };

/// Grades one completed conversation.
export function scoreConversation(scenario, run) {
  const expect = scenario.expect ?? {};
  const names = run.calls.map((call) => call.name);

  if (run.error) return { outcome: "error", detail: run.error };

  // Termination first. A model still calling tools at the turn cap has not answered
  // the question, so nothing else about the run is meaningful.
  if (!run.terminated) {
    return {
      outcome: "runaway",
      detail: `hit ${scenario.maxTurns ?? 6}-turn cap after ${names.length} calls: ${names.join(" -> ") || "none"}`,
    };
  }

  const forbidden = new Set(expect.mustNotCall ?? []);
  const violation = names.find((name) => forbidden.has(name));
  if (violation) return { outcome: "forbidden", detail: `called forbidden tool "${violation}"` };

  const missing = (expect.mustCall ?? []).filter((name) => !names.includes(name));
  if (missing.length) {
    return {
      outcome: "missing_call",
      detail: `never called ${missing.join(", ")} (called: ${names.join(" -> ") || "nothing"})`,
    };
  }

  // Relative order only — extra calls between two required ones are fine, since
  // there is usually more than one reasonable route to the same answer.
  if (expect.order) {
    const positions = expect.order.map((name) => names.indexOf(name));
    for (let i = 1; i < positions.length; i += 1) {
      if (positions[i] < positions[i - 1]) {
        return {
          outcome: "wrong_order",
          detail: `expected ${expect.order.join(" -> ")}, got ${names.join(" -> ")}`,
        };
      }
    }
  }

  // The same tool with identical arguments twice is wasted latency and, in a real
  // agent, a duplicated side effect. Distinct arguments are legitimate iteration.
  const seen = new Set();
  for (const call of run.calls) {
    const key = `${call.name}:${JSON.stringify(call.args ?? {})}`;
    if (seen.has(key)) {
      return { outcome: "redundant_call", detail: `repeated ${call.name} with identical arguments` };
    }
    seen.add(key);
  }

  if (expect.maxCalls !== undefined && names.length > expect.maxCalls) {
    return {
      outcome: "redundant_call",
      detail: `${names.length} calls exceeds budget of ${expect.maxCalls}: ${names.join(" -> ")}`,
    };
  }

  // Did the final answer actually use what the tools returned? Substring matching is
  // crude, but the strings are chosen to appear ONLY in stubbed tool output — so a
  // hit is evidence the model read the result rather than improvised a plausible answer.
  const text = (run.finalText ?? "").toLowerCase();
  const absent = (expect.finalMustMention ?? []).filter(
    (needle) => !text.includes(needle.toLowerCase())
  );
  if (absent.length) {
    return {
      outcome: "no_synthesis",
      detail: `final answer never mentions ${absent.map((s) => `"${s}"`).join(", ")}`,
    };
  }

  const banned = (expect.finalMustNotMention ?? []).filter((needle) =>
    text.includes(needle.toLowerCase())
  );
  if (banned.length) {
    return {
      outcome: "no_synthesis",
      detail: `final answer asserts ${banned.map((s) => `"${s}"`).join(", ")} it could not know`,
    };
  }

  return { outcome: "pass", detail: null };
}

export function summariseConversations(rows) {
  const counts = Object.fromEntries(OUTCOMES.map((name) => [name, 0]));
  for (const row of rows) counts[row.outcome] += 1;
  const total = rows.length || 1;

  const median = (values) => {
    if (!values.length) return null;
    const sorted = [...values].sort((a, b) => a - b);
    return Number(sorted[Math.floor(sorted.length / 2)].toFixed(1));
  };

  return {
    total: rows.length,
    counts,
    passRate: Number(((counts.pass / total) * 100).toFixed(1)),
    // Reported on its own: a runaway agent is a different problem from an
    // inaccurate one. It burns the user's time and, with real tools, repeats
    // side effects — so it gates adoption independently of the pass rate.
    runaways: counts.runaway,
    medianCalls: median(rows.map((row) => row.callCount)),
    medianWallMs: median(rows.map((row) => row.wallMs).filter(Boolean)),
  };
}
