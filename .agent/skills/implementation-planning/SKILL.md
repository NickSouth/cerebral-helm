---
name: implementation-planning
description: create evidence-based implementation plans for cerebralhelm linear issues. use when the user provides a linear ticket identifier and wants a complete implementation plan based on the issue, its descendants, acceptance criteria, dependencies, current codebase, project specifications, wiki, and verified integration contracts. produce an ordered sequence of reviewable commit-sized increments without modifying code or linear.
---

# Implementation Planning

Create a complete implementation plan for the Linear issue identified by the user.

Treat the supplied issue as the planning root. It may be either a parent issue or a sub-issue.

This is a read-only planning workflow. Do not edit code, update Linear, create commits, or begin implementation.

## Required Input

Require a Linear ticket identifier such as `TEAM-123`.

If the identifier is missing or cannot be resolved, ask the user for the correct ticket identifier or URL. Never guess which issue they mean.

## Source Precedence

Use sources in this order:

1. The user's latest explicit instructions
2. `.agent/spec/MVP-PRD.md`
3. The planning root's explicit acceptance criteria
4. `.agent/spec/TECH-STACK.md`
5. Relevant contracts, schemas, ADRs, tests, and existing code
6. Relevant descendant Linear issues
7. `wiki/NORTH-STAR.md`
8. Supporting Linear comments, linked issues, and project context

The MVP PRD governs current scope. The North Star governs long-term compatibility but does not automatically add future features to the current issue.

If authoritative sources conflict, identify the conflict and ask the user before making a consequential assumption.

## Workflow

### 1. Read Repository Instructions

Read `AGENTS.md` before beginning.

Follow all repository-specific instructions, boundaries, terminology, and source-of-truth rules.

Inspect the working tree without modifying it. Existing uncommitted changes may represent current user work and must be considered when evaluating the codebase.

### 2. Retrieve the Planning Root

Use the connected Linear tools to retrieve the supplied issue.

Collect:

- Identifier and title
- Description
- Explicit acceptance criteria and checklists
- Status, priority, estimate, labels, project, and milestone
- Parent issue and ancestor context
- Direct and indirect sub-issues
- Blocking, blocked-by, duplicate, and related relationships
- Relevant comments or linked specifications
- Any implementation notes or dependencies

Do not modify the issue or any related Linear data.

### 3. Build the Issue Hierarchy

Treat the supplied ticket as the planning root.

If it has sub-issues, recursively gather all descendants and preserve their hierarchy.

If it is itself a sub-issue:

- Read its parent and ancestor chain for product context.
- Inspect siblings only when they establish shared contracts, ordering, or dependencies.
- Do not silently include sibling functionality in the implementation scope.
- Keep the resulting plan scoped to the supplied issue and its descendants.

Distinguish between:

- Explicit requirements
- Explicit acceptance criteria
- Supporting context
- Dependencies owned by other issues
- Inferred requirements

Never present an inferred requirement as though it came directly from Linear.

### 4. Read the Project Context

Read only the portions of the following documents relevant to the issue:

- `AGENTS.md`
- `.agent/spec/MVP-PRD.md`
- `.agent/spec/TECH-STACK.md`
- `wiki/NORTH-STAR.md`
- Relevant ADRs
- Relevant architecture and compatibility documentation
- Relevant configuration and schemas

Use the project's canonical names and architectural boundaries.

Do not expand the issue merely because a future capability appears in the North Star.

### 5. Inspect the Current Codebase

Use repository search and code navigation to determine the actual implementation state.

Inspect:

- Repository and package structure
- Package manifests and dependency versions
- Existing domain boundaries
- Relevant commands, events, schemas, and generated types
- Current implementations and adapters
- Configuration conventions
- Database migrations and repositories
- UI components and native bridge boundaries
- Tests, fixtures, mocks, and helper utilities
- Call sites and consumers of anything that may change

Trace behavior far enough to understand both producers and consumers of affected contracts.

Do not assume a planned file exists merely because a specification mentions it. Clearly distinguish between implemented, partially implemented, stubbed, and absent behavior.

### 6. Verify Contracts and Integrations

Never guess how a contract or integration works.

Before planning changes involving a contract:

- Locate its actual schema, type definition, tests, and call sites.
- Identify its current version and compatibility expectations.
- Determine which layer owns it.
- Identify every affected producer and consumer.

Before planning an external integration:

- Identify the actual library, SDK, API, or platform version in use.
- Consult official documentation for that version.
- Verify permissions, lifecycle, error behavior, and platform limitations.
- Separate verified behavior from assumptions.

Mocks and fixtures are evidence of expected local behavior, not proof of how a production provider behaves.

If required behavior cannot be verified, record it as an unresolved question rather than inventing an answer.

### 7. Reconcile Requirements With Reality

Compare the Linear hierarchy, acceptance criteria, project documents, and codebase.

Identify:

- Requirements already satisfied
- Requirements partially implemented
- Missing behavior
- Required contract changes
- Required migrations or compatibility work
- Tests that already cover the behavior
- Missing regression coverage
- Dependencies on unfinished issues
- Scope that conflicts with the MVP boundary
- Acceptance criteria that are ambiguous or unverifiable

Ask questions before finalizing the plan when uncertainty would materially change:

- Architecture
- Public or versioned contracts
- Persistent data
- Security or confirmation policy
- User-visible behavior
- External integration behavior
- The boundaries between Linear issues

Do not ask questions whose answers can be discovered from the repository or authoritative documentation.

### 8. Create the Implementation Sequence

Plan the entire supplied issue as an ordered sequence of commit-sized increments.

A commit-sized increment must:

- Deliver one coherent behavior or enabling contract
- Be understandable and reviewable independently
- Leave the repository in a working state
- Include its own appropriate tests
- Avoid mixing unrelated refactors or features
- Respect dependency order
- Be small enough for the user to review before continuing

Use the Linear sub-issue structure when it reflects sound implementation boundaries, but do not follow it mechanically. Split oversized sub-issues into multiple increments and combine only tightly coupled work that cannot be validated separately.

If the supplied issue is already small, the plan may contain one increment.

Order work so that contracts and deterministic domain behavior generally precede adapters and UI consumers. Do not create abstractions solely for hypothetical future use.

For every increment, specify:

- Goal
- Linear requirements covered
- Expected implementation changes
- Likely files or modules affected
- Contract, schema, configuration, or migration effects
- Tests and verification
- Completion criteria
- Dependencies
- Explicitly deferred work

Use likely file paths only when supported by the current repository. Label paths as new when they do not yet exist.

### 9. Validate the Plan

Before returning the plan, confirm that:

- Every explicit acceptance criterion is covered
- Every descendant issue is covered, deferred with a reason, or identified as out of scope
- The sequence respects technical and issue dependencies
- No increment silently contains multiple unrelated commits
- Contracts are verified rather than invented
- Tests scale with the risk and affected surface
- User-owned state and compatibility concerns are addressed
- Future architecture is preserved without importing future scope
- Open questions are genuinely unresolved
- No code or Linear data was modified

## Output Format

Use the following structure:

# Implementation Plan: `<TICKET-ID>` - `<Title>`

## Objective

Summarize the user-visible or architectural outcome in a short paragraph.

## Scope

State what the planning root includes and explicitly excludes.

Identify whether the planning root is a parent issue or a sub-issue.

## Issue Hierarchy

Present the planning root and relevant descendants in dependency order.

For each issue, include:

- Identifier and title
- Role in the plan
- Dependencies
- Current status

## Acceptance Criteria

Create a normalized checklist of explicit acceptance criteria.

For each criterion, cite its source ticket or specification.

Keep inferred requirements in a separate subsection labeled `Inferred Requirements`.

## Current Implementation

Explain:

- What already exists
- What is partial or stubbed
- What is missing
- Which contracts and modules are involved
- Which tests currently cover the area

Reference exact repository paths where useful.

## Technical Approach

Describe the intended architecture and flow.

Include:

- Ownership boundaries
- Relevant contracts and schemas
- Data flow
- Error and failure behavior
- Configuration behavior
- Security and confirmation implications
- Compatibility or migration considerations

Clearly label any proposed decision that is not already established by the repository.

## Implementation Sequence

### Increment 1: `<Reviewable outcome>`

**Goal:**  
Describe the single coherent result.

**Requirements covered:**  
List the Linear issues and acceptance criteria addressed.

**Changes:**  
Describe the concrete implementation work.

**Likely files:**  
List verified existing paths and clearly labeled new paths.

**Contracts and data:**  
Describe schema, API, configuration, migration, or compatibility effects.

**Tests:**  
List the required unit, contract, integration, browser, migration, or platform checks.

**Completion criteria:**  
State the observable conditions that make this increment complete.

**Dependencies:**  
List required earlier increments or external issue dependencies.

**Deferred:**  
State adjacent work intentionally left for later.

Repeat this section for every increment.

## Acceptance Coverage

Provide a table mapping every explicit acceptance criterion to the increment that satisfies and verifies it.

| Acceptance criterion | Source | Increment | Verification |
|---|---|---|---|

## Risks and Edge Cases

List concrete implementation, migration, security, platform, or compatibility risks.

Avoid generic risks that do not affect the plan.

## Open Questions

Include only questions that cannot be answered from Linear, the repository, project documentation, or official integration documentation.

If none remain, state `None`.

## Recommended First Increment

Name the first commit-sized increment the user should authorize for implementation.

Do not implement it.

## Planning Rules

- Do not modify code.
- Do not modify Linear.
- Do not create commits.
- Do not invent contracts or integration behavior.
- Do not treat mocks as production documentation.
- Do not broaden MVP scope from the North Star.
- Do not hide unresolved uncertainty inside assumptions.
- Do not plan multiple unrelated behaviors as one increment.
- Do not continue into implementation without a new user prompt.