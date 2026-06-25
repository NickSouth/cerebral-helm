# AGENTS.md

## Project Context

CerebralHelm is a local-first agentic desktop environment for macOS, centered around the voice assistant Heimlich. It runs on top of macOS as a persistent dashboard, command surface, mode engine, knowledge system, and launcher for narrow tools and specialized agents.

It is not an operating system replacement or a general chatbot with unrestricted computer access. The goal is a reliable, context-aware front door to the user's digital life.

Canonical product vocabulary:

- Assistant: Heimlich
- Modes: Executive, Developer, School, Entertainment
- Agent surfaces: Research Analyst, Financial Advisor, Project Manager, System Janitor
- Durable knowledge: Markdown plus SQLite
- Vector indexes: Disposable and rebuildable
- Core principle: Useful before intelligent

The current MVP builds the deterministic foundation first. Future models, voice, mobile clients, integrations, and agents must extend the same contracts rather than create parallel systems.

## Sources of Truth

Before implementing anything, read the relevant documentation:

1. The user's latest explicit instructions
2. `.agent/spec/MVP-PRD.md` for current scope, requirements, and acceptance criteria
3. `.agent/spec/TECH-STACK.md` for approved technologies and implementation decisions
4. `wiki/NORTH-STAR.md` for long-term product intent
5. Relevant ADRs, schemas, tests, and existing code

The MVP PRD controls current scope. The North Star informs future compatibility but does not automatically place future features inside the MVP.

Never guess how something should be implemented when the answer may exist in the repository. Search the specs, wiki, ADRs, contracts, and existing patterns first.

If sources conflict, requirements are unclear, or a decision would materially affect architecture, behavior, security, or stored data, stop and ask the user.

## Verify, Do Not Assume

Never assume that you know:

- The shape of a command, event, tool, bridge, storage, or provider contract
- How an external API, framework, SDK, operating-system feature, or integration behaves
- Which library version or platform capability is available
- What a mock implementation implies about the production integration
- Whether a future capability belongs in the current scope

Inspect the actual schema, type, test, configuration, and official integration documentation before implementing against it.

Do not invent fields, endpoints, permissions, lifecycle behavior, or error semantics. If the necessary information cannot be verified, ask before continuing.

## Work Cadence

Work in one coherent, commit-sized increment at a time.

For each prompt:

1. Inspect the relevant code, contracts, tests, and documentation.
2. Resolve important uncertainty before editing.
3. Implement the smallest complete vertical slice that satisfies the request.
4. Add or update appropriate tests and documentation.
5. Run the relevant verification.
6. Stop and return the work for user review.

Do not continue into the next issue, sub-issue, feature, or logical commit without another prompt.

Do not create a Git commit unless the user explicitly asks. The user will review the increment, commit it, and then prompt the next step.

Avoid unrelated refactors and opportunistic features. A commit-sized increment should leave the repository coherent, tested, and understandable on its own.

## Completion Report

At the end of every implementation increment, report:

- What was built
- Which files changed
- What tests or checks were run
- Any important implementation decisions
- Any unresolved risks or questions
- The next logical increment, without implementing it

Explain the implementation clearly enough that the user can understand and review what was built. Do not hide meaningful behavior behind a vague summary.

## Engineering Principles

Always build the current increment with the complete CerebralHelm vision in mind, without prematurely implementing future scope.

Preserve these architectural truths:

- All input sources converge on one versioned command bus.
- UI components express intent and render state; they do not directly control the platform.
- All UI related work should be done in line with the design spec and visual references files in the repo
- Platform, provider, model, and storage behavior lives behind replaceable adapters.
- Tools are narrow, explicit, typed, permission-aware, and independently testable.
- Risk classification and confirmation policy remain deterministic and outside models.
- Models may propose actions but never bypass policy or invoke unrestricted capabilities.
- Configuration belongs outside hardcoded application logic where practical.
- Durable personal state remains local, inspectable, portable, and migration-safe.
- User configuration, preferences, knowledge, secrets, and history must survive updates.
- External integrations should be provider-neutral at the core boundary.
- Contracts should be versioned before adding production providers.
- Missing integrations should degrade gracefully rather than disable the command surface.
- Tests should cover contracts, regressions, migrations, failures, and security boundaries.

Prefer modular boundaries that make future voice, iOS, Google Workspace, model routing, agents, semantic retrieval, and macOS capabilities additive rather than requiring rewrites.

Do not over-engineer speculative abstractions. Add extension points when the North Star or MVP PRD establishes a real future requirement, and implement only the behavior required by the current slice.

## Safety and State

Never bypass confirmation, permissions, allowlists, or tool policy for convenience.

Do not expose secrets in code, configuration, logs, fixtures, or test snapshots.

Treat destructive writes, external communication, process execution, financial activity, authentication, and personal data as sensitive boundaries.

Do not silently reset, replace, or migrate user-owned state. Any stateful change must have explicit behavior, tests, and a recovery path.