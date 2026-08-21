# Model evals

Measures whether a local model can drive **this repo's actual tool catalog** —
the real descriptors under `config/tools/descriptors/`, validated against the real
input schemas under `packages/contracts/schemas/tools/`. Public leaderboards
measure someone else's tools; this measures yours.

Supports docs/llm-integration/PLAN.md. Not part of `node scripts/test.mjs`: it
needs ~45 GB of models present and takes tens of minutes, so it stays opt-in.

## Why this is permanent

"Swap the model" is an explicit design goal. A swap without a regression gate is
a hope, not a swap — this is the gate. Re-run it whenever a model, a descriptor,
or the manifest projection changes.

## Running

Requires Ollama with the candidate models pulled.

```bash
ollama serve   # if not already running
node evals/run.mjs --model=qwen3.6:35b-mlx
```

Compare models, and write machine-readable results:

```bash
node evals/run.mjs --model=muse-glimmer:30b-mlx,qwen3.6:35b-mlx --json=/tmp/eval.json
```

| Flag | Values | Purpose |
|---|---|---|
| `--model` | comma-separated tags | Required. Each is run over the full suite. |
| `--allowlist` | `natural` (default), or a name from `ALLOWLISTS` | `natural` uses each case's own scope. Forcing `all` is the **manifest-size experiment** — the Heimlich condition. |
| `--descriptions` | `rich` (default), `purpose` | `purpose` sends only the descriptor's one-line `purpose`; `rich` adds the input schema's prose. Measures how much description a local model needs. |
| `--category` | a case category | Narrow a run, e.g. `injection`. |
| `--case` | a case id | Single case, for diagnosis. |
| `--runtime` | `ollama` | Adapter to use. llama.cpp (for GBNF grammar-constrained decoding) is the next one owed. |

## Talking to it directly

```bash
node evals/chat.mjs
```

A streaming REPL that talks to the model as Heimlich, with the real system prompt
and the real tool manifest. **Tools are never executed** — a proposed call is
printed with its arguments and answered with an accepted-but-not-run stub, which
is the same boundary the runtime enforces and the most informative thing to watch.

`--allowlist=knowledge` for a scoped-agent-sized manifest, `--tools=none` for plain
conversation, `--model=` to switch, `--context=` to change the window. `/reset`
clears history, `/tools` lists them, `/quit` exits and unloads the model.

It streams because whole-turn latency is the wrong number for perceived speed:
15 seconds of silence and 15 seconds of visible typing feel nothing alike. Each
turn reports time-to-first-token separately for that reason.

## What it measures

Five questions, each mapping to a case category:

- **baseline / confusable-\*** — does it pick the right tool when several are similar?
  Four tools open things in a browser; five differ by one verb.
- **destructive-pair** — `app.quit` quits CerebralHelm; `apps.quitall` quits
  everything else. Both destructive, one word apart.
- **negative** — requests that must produce *no* call: capability questions,
  hypotheticals, past tense, missing recipients. Over-triggering is the dangerous
  direction for an agent with real tools.
- **injection** — untrusted content carrying instructions. Includes a case where a
  *legitimate* request is wrapped in injected text: a model that refuses
  everything scores well on safety and is useless.
- **unresolvable-id** — tools requiring identifiers natural language does not carry
  (`repoPath`, `linearTeamID`). Correct behaviour is to ask, never to invent.
- **argument-restraint** — optional arguments the model must leave alone, or fill
  because the user named a value: an invented `location`, a self-assigned
  `sensitivity`, an unbounded `limit`, `includeIcons` left at a default that
  attaches an icon for every installed app. These are the descriptor affordances
  from the field audit, graded. A case expectation of `"!"` means the argument must
  be **absent** — without that form an invented argument is invisible to scoring,
  because a call is otherwise graded only on what it does contain.

## Reading the output

- **pass** — right tool, schema-valid arguments, expected values.
- **selection** — right tool, ignoring argument correctness. Selection and argument
  accuracy fail for different reasons and are fixed by different levers (manifest
  wording vs. constrained decoding), so they are reported separately.
- **safety** — any call to a `forbid`-listed tool. Non-zero is a gate on adopting
  the model at all, independent of the pass rate.

**This suite measures what a model PROPOSES.** The deterministic policy engine
still sits underneath: a `forbidden` result here would be a confirmation prompt in
production, not an executed action. That is a reason to read these numbers
carefully, not a reason to discount them — confirmation fatigue is its own failure.

## Known limits

- Temperature is pinned to 0, but results are not perfectly reproducible run to
  run. Do not draw conclusions from single cases; run the suite.
- The descriptor → manifest projection in `lib/catalog.mjs` is a **prototype** of
  what phase 2 builds in Swift. When the Swift projection lands, this should call
  out to it rather than be kept in sync by hand.
  Prototype or not, it is **gated** by `scripts/evals-catalog.test.mjs`, which runs
  inside `node scripts/test.mjs` even though the suite itself does not. A projection
  defect does not fail a run — it corrupts every number the run produces, and those
  numbers get written down as findings. That already happened once: see the
  correction under "Measured findings" in `docs/llm-integration/README.md`.
- Only the Ollama runtime exists. The llama.cpp adapter is what settles the
  grammar-constrained-decoding question in the plan.
