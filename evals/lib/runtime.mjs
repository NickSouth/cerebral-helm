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

export const RUNTIMES = {
  ollama: { id: "ollama", chat: ollamaChat, unload: ollamaUnload },
};

/// Fails fast with an actionable message rather than 29 identical connection errors.
export async function assertRuntimeReady(runtimeId, model) {
  if (runtimeId !== "ollama") throw new Error(`Unknown runtime: ${runtimeId}`);

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
