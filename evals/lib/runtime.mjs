// Runtime adapters — the thing under test alongside the model itself.
//
// This mirrors, deliberately, the provider port that phase 0 of
// docs/llm-integration/PLAN.md specifies: the harness must be able to swap the
// *runtime* (Ollama/MLX today, llama.cpp with GBNF grammars next) without the
// cases or the scoring changing. That swap is an open question in the plan —
// llama.cpp has integrated grammar-constrained decoding, MLX does not — and it
// only gets settled by running the same cases through both.

const OLLAMA_HOST = process.env.OLLAMA_HOST ?? "http://localhost:11434";

/// Nanoseconds-to-tokens-per-second, guarding the zero-duration case.
function rate(count, nanos) {
  if (!count || !nanos) return null;
  return Number(((count / nanos) * 1e9).toFixed(1));
}

/// One tool-calling turn against Ollama's native chat API.
///
/// Temperature is pinned to 0. This measures capability, not sampling luck — a
/// model that only picks the right tool sometimes is a model that will surprise
/// the user, and the confirmation layer should not be the thing that catches it.
async function ollamaChat({
  model,
  system,
  prompt,
  messages,
  tools,
  signal,
  contextTokens = 16384,
}) {
  const started = performance.now();

  // Two calling conventions on purpose. The single-turn suite passes system+prompt;
  // the conversation suite passes a full `messages` array so tool results can be fed
  // back as `role: "tool"` turns. Keeping one transport for both means a change to
  // timing, options, or error handling can never apply to only one of the suites.
  const turns = messages ?? [
    { role: "system", content: system },
    { role: "user", content: prompt },
  ];

  const response = await fetch(`${OLLAMA_HOST}/api/chat`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      model,
      messages: turns,
      tools,
      stream: false,
      // `num_ctx` is capped deliberately. Left to itself Ollama allocates the model's
      // FULL advertised window — 131K for Glimmer, 262K for Qwen — and the KV cache for
      // that took a 21GB model to 29GB resident. No case here needs more than a few
      // thousand tokens, and the same lever applies in production: context size is a
      // memory decision as much as a capability one.
      options: { temperature: 0, num_ctx: contextTokens },
    }),
    signal,
  });

  if (!response.ok) {
    throw new Error(`Ollama ${response.status}: ${(await response.text()).slice(0, 400)}`);
  }

  const body = await response.json();
  const calls = body.message?.tool_calls ?? [];

  return {
    // A model may emit several calls; the first is what would execute first, and
    // extra calls are themselves a finding (recorded as `extraCalls`).
    toolName: calls[0]?.function?.name ?? null,
    toolArgs: calls[0]?.function?.arguments ?? null,
    extraCalls: calls.slice(1).map((call) => call.function?.name).filter(Boolean),
    text: body.message?.content ?? "",
    // Every call the turn emitted, and the assistant message verbatim. The
    // conversation loop must append the model's own message back onto the thread
    // before adding tool results, or the model sees results for calls it has no
    // record of making and re-issues them — which reads as a runaway loop when it
    // is really a harness bug.
    calls: calls.map((call) => ({ name: call.function?.name, args: call.function?.arguments })),
    assistantMessage: body.message ?? null,
    timing: {
      wallMs: Math.round(performance.now() - started),
      promptTokens: body.prompt_eval_count ?? null,
      outputTokens: body.eval_count ?? null,
      // Prefill matters more than decode for this workload: a large system
      // prompt plus a 29-tool manifest is re-read on every turn unless cached.
      prefillTokPerSec: rate(body.prompt_eval_count, body.prompt_eval_duration),
      decodeTokPerSec: rate(body.eval_count, body.eval_duration),
    },
  };
}

/// Evicts a model from memory immediately.
///
/// MUST be called between models. Ollama's default `keep_alive` is 5 minutes, so a
/// sequential comparison run otherwise holds BOTH models resident — measured at
/// 29GB + 22GB against a ~48GB GPU budget, which drove 18GB of swap and made every
/// remaining request meaningless. The first version of this harness omitted it and a
/// full run went from ~12 minutes to over 30 while thrashing the disk.
async function ollamaUnload(model) {
  await fetch(`${OLLAMA_HOST}/api/generate`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ model, keep_alive: 0 }),
  }).catch(() => {});
}

/// Fails fast with an actionable message rather than 29 identical connection errors.
async function ollamaReady(model) {
  let tags;
  try {
    tags = await (await fetch(`${OLLAMA_HOST}/api/tags`)).json();
  } catch {
    throw new Error(`Cannot reach Ollama at ${OLLAMA_HOST}. Start it with: ollama serve`);
  }

  const installed = (tags.models ?? []).map((entry) => entry.name);
  if (!installed.includes(model)) {
    throw new Error(
      `Model "${model}" is not installed.\n` +
        `  Installed: ${installed.join(", ") || "(none)"}\n` +
        `  Pull it with: ollama pull ${model}`
    );
  }
}

// ---------------------------------------------------------------------------
// llama.cpp
//
// The second runtime, and the reason the seam above exists: llama.cpp compiles a
// tool's JSON Schema to a GBNF grammar and masks invalid tokens at every sampling
// step, so an argument outside the schema is not unlikely — it is unreachable.
// Verified here, not assumed: given a schema whose only legal `kind` was
// `zqx-sentinel` and a user explicitly demanding `meeting`, the model emitted
// `zqx-sentinel`. `--jinja` is on by default and no extra flag is needed.
//
// Two structural differences from Ollama that this adapter has to absorb:
//
//   1. MODEL BINDING. Ollama picks a model per request; `llama-server` serves ONE
//      model per process and IGNORES the `model` field. A typo would therefore
//      silently benchmark whatever happens to be loaded, so `llamaReady` compares
//      the requested name against what the server reports and refuses a mismatch.
//   2. CONTEXT SIZING. `num_ctx` is per-request on Ollama; `-c` is per-LAUNCH here.
//      This adapter cannot honour a per-request `contextTokens`, so it asserts the
//      served window is large enough instead. Silently serving a smaller window
//      would invalidate every number the run produces.

const LLAMA_HOST = process.env.LLAMA_HOST ?? "http://localhost:8080";

/// Rewrites the harness's Ollama-shaped transcript into OpenAI shape.
///
/// `lib/conversation.mjs` appends tool results as `{role, name, content}`, which is
/// Ollama's convention — the loop is shared, so the translation belongs here rather
/// than in the loop. OpenAI keys a result by `tool_call_id`, so each `tool` turn is
/// matched back to the call it answers by name, walking the assistant turns already
/// on the thread. Left untranslated the server sees results for calls it cannot
/// correlate and the model re-issues them, which reads as a runaway loop.
export function toOpenAITurns(turns) {
  const idsByName = new Map();

  return turns.map((turn) => {
    if (turn.role === "assistant" && Array.isArray(turn.tool_calls)) {
      for (const call of turn.tool_calls) {
        if (call.id && call.function?.name) idsByName.set(call.function.name, call.id);
      }
      return turn;
    }

    if (turn.role !== "tool") return turn;

    const { name, ...rest } = turn;
    const id = turn.tool_call_id ?? idsByName.get(name);
    // A result we cannot correlate is passed through with its name only. The server
    // is lenient about it, and dropping the turn outright would be worse: the model
    // would never learn what its call returned.
    return id ? { ...rest, tool_call_id: id } : turn;
  });
}

/// One tool-calling turn against llama.cpp's OpenAI-compatible endpoint.
async function llamaChat({ model, system, prompt, messages, tools, signal }) {
  const started = performance.now();

  // Same two calling conventions as the Ollama adapter, for the same reason.
  const turns = messages ?? [
    { role: "system", content: system },
    { role: "user", content: prompt },
  ];

  const response = await fetch(`${LLAMA_HOST}/v1/chat/completions`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      model,
      messages: toOpenAITurns(turns),
      // Sent even when empty is not the same as omitted: an empty `tools` array
      // still selects the template's tool-calling branch on some chat templates,
      // so it is omitted entirely when there are none.
      ...(tools?.length ? { tools } : {}),
      stream: false,
      temperature: 0,
    }),
    signal,
  });

  if (!response.ok) {
    throw new Error(`llama.cpp ${response.status}: ${(await response.text()).slice(0, 400)}`);
  }

  const body = await response.json();
  const message = body.choices?.[0]?.message ?? {};
  const rawCalls = message.tool_calls ?? [];

  // OpenAI serialises arguments as a JSON STRING; Ollama hands back an object. A
  // string that will not parse is a finding, not a crash — malformed arguments are
  // precisely what this suite exists to count — so it degrades to null and lets the
  // scorer record a schema failure.
  const calls = rawCalls.map((call) => {
    let args = null;
    try {
      args = JSON.parse(call.function?.arguments ?? "{}");
    } catch {
      args = null;
    }
    return { name: call.function?.name, args };
  });

  const timings = body.timings ?? {};

  return {
    toolName: calls[0]?.name ?? null,
    toolArgs: calls[0]?.args ?? null,
    extraCalls: calls.slice(1).map((call) => call.name).filter(Boolean),
    text: message.content ?? "",
    calls,
    // Returned verbatim so the conversation loop can append the model's own turn,
    // ids included — those ids are what the next `tool` turn correlates against.
    assistantMessage: body.choices?.[0]?.message ?? null,
    timing: {
      wallMs: Math.round(performance.now() - started),
      promptTokens: body.usage?.prompt_tokens ?? timings.prompt_n ?? null,
      outputTokens: body.usage?.completion_tokens ?? timings.predicted_n ?? null,
      // Reported directly by the server rather than derived, unlike Ollama's
      // nanosecond durations. Rounded to match the other adapter's precision.
      prefillTokPerSec: timings.prompt_per_second
        ? Number(timings.prompt_per_second.toFixed(1))
        : null,
      decodeTokPerSec: timings.predicted_per_second
        ? Number(timings.predicted_per_second.toFixed(1))
        : null,
    },
  };
}

/// No-op: with llama.cpp the memory IS the process.
///
/// Present so the seam stays uniform — `run.mjs` calls `unload?.()` between models,
/// and a runtime that cannot evict on demand is not a failed run. Freeing this
/// model means stopping the server, which the harness deliberately does not own.
async function llamaUnload() {}

/// Verifies the server is up, serving the requested model, with a big enough window.
async function llamaReady(model, { contextTokens = 16384 } = {}) {
  let props;
  try {
    props = await (await fetch(`${LLAMA_HOST}/props`)).json();
  } catch {
    throw new Error(
      `Cannot reach llama.cpp at ${LLAMA_HOST}. Start it with:\n` +
        `  llama-server -hf <user>/<repo>:<quant> -c ${contextTokens} -a ${model} --port 8080`
    );
  }

  const servedContext = props.default_generation_settings?.n_ctx;
  if (servedContext && servedContext < contextTokens) {
    throw new Error(
      `llama.cpp is serving a ${servedContext}-token context but the suite asks for ${contextTokens}.\n` +
        `  Context is a LAUNCH flag here, not a per-request option — restart with: -c ${contextTokens}`
    );
  }

  // The server ignores the `model` field in a request, so a wrong `--model` would
  // silently benchmark whatever is loaded. Compare against what it reports instead.
  let served = [];
  try {
    const models = await (await fetch(`${LLAMA_HOST}/v1/models`)).json();
    served = (models.data ?? []).map((entry) => entry.id);
  } catch {
    // Older builds may not expose the endpoint; the context check above already ran.
    return;
  }

  if (served.length && !served.includes(model)) {
    throw new Error(
      `llama.cpp is serving "${served.join(", ")}", not "${model}".\n` +
        `  This runtime ignores the model field in a request, so the mismatch would be silent.\n` +
        `  Relaunch with: -a ${model}   (or pass --model=${served[0]})`
    );
  }
}

export const RUNTIMES = {
  ollama: { id: "ollama", chat: ollamaChat, unload: ollamaUnload, ready: ollamaReady },
  llamacpp: { id: "llamacpp", chat: llamaChat, unload: llamaUnload, ready: llamaReady },
};

/// Fails fast with an actionable message rather than 29 identical connection errors.
export async function assertRuntimeReady(runtimeId, model, options = {}) {
  const runtime = RUNTIMES[runtimeId];
  if (!runtime) {
    throw new Error(`Unknown runtime: ${runtimeId}. Known: ${Object.keys(RUNTIMES).join(", ")}`);
  }
  await runtime.ready(model, options);
}
