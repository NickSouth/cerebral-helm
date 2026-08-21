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
| `--runtime` | `ollama` (default), `llamacpp` | Which inference runtime serves the cases. Same cases, same scoring — see below. |

### Running against llama.cpp

llama.cpp compiles a tool's JSON Schema to a GBNF grammar and masks invalid tokens
at every sampling step, so an argument outside the schema is **unreachable** rather
than merely unlikely. `--jinja` is on by default; no extra flag is needed.

It serves **one model per process**, and unlike Ollama it needs a GGUF — the `-mlx`
tags in `ollama list` are MLX tensors and cannot be loaded here. `-hf` downloads one:

```bash
llama-server -hf unsloth/Qwen3-4B-Instruct-2507-GGUF:Q4_K_M -c 16384 -a eval-small --port 8080
```

```bash
node evals/run.mjs --runtime=llamacpp --model=eval-small
```

Two differences the adapter enforces rather than papers over:

- **`--model` must match the server's alias** (`-a`). This runtime ignores the model
  field in a request, so a typo would silently benchmark whatever is loaded.
- **Context is a launch flag** (`-c`), not a per-request option. The adapter refuses
  to run if the served window is smaller than the suite asks for; a silently smaller
  window would invalidate every number in the run.

`unload` is a no-op here — the memory is the process. Stop the server to free it, and
stop the *other* runtime before measuring either: two resident models oversubscribe
the GPU budget and every timing after that point is swap, not inference.

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

## The composer suite

`run-report.mjs` measures the passive tier instead of tool calling: a typed snapshot
in, `ReportDocument` blocks out, validated with ajv against the real
`report-document.schema.json`. It runs through the same runtime seam.

```bash
node evals/run-report.mjs --runtime=ollama   --model=qwen3.6:35b-mlx --reps=6
node evals/run-report.mjs --runtime=llamacpp --model=<server alias> --reps=6
```

| Flag | Values | Purpose |
|---|---|---|
| `--runtime` | `ollama` (default), `llamacpp` | Who serves it. The pairing that settled the grammar question. |
| `--format` | `schema` (default), `json`, `none` | `schema` uses the runtime's structured-output mode; `none` just asks in the prompt. |
| `--reps` | integer, default 1 | Repeat the suite. **Use it.** See below. |
| `--think` | `false` (default), `true` | Off by default: composition from a typed snapshot is rendering, not reasoning. |
| `--snapshot` | a snapshot id | Narrow to one case. |

**Read `leaf-type violations`, not just the pass rate.** It is printed on its own line
because it is the number the runtime question turns on, and an aggregate pass rate
buries it among dropped facts. With the same schema supplied, Ollama produced a
schema-invalid document on **6 of 6** runs of one snapshot and llama.cpp on **0 of 6**.

**One repetition proves nothing here.** Temperature is 0.4 in this suite, unlike the
tool suites which pin it to 0. A single sample once showed a violation appearing and
vanishing between runs and briefly read as a decisive result; six repetitions gave the
real rates.

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
- `chat.mjs` is Ollama-only: it streams directly rather than through the runtime
  seam, because time-to-first-token is the number it exists to show. It is a REPL,
  not a measurement surface, so it was left alone when the second runtime landed.
- The composer's `mustMention` check is a case-insensitive substring match over the
  whole document, so it catches a dropped fact but not a misattributed one. A block
  that names the right figure against the wrong label still passes.
