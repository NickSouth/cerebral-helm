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
async function ollamaChat({ model, system, prompt, tools, signal }) {
  const started = performance.now();

  const response = await fetch(`${OLLAMA_HOST}/api/chat`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      model,
      messages: [
        { role: "system", content: system },
        { role: "user", content: prompt },
      ],
      tools,
      stream: false,
      options: { temperature: 0 },
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

export const RUNTIMES = {
  ollama: { id: "ollama", chat: ollamaChat },
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
