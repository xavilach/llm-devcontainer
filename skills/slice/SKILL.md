---
name: slice
description: "Phase 3 of engineering-flow. Break the spec into vertical tracer-bullet tickets with explicit blocking edges, one markdown file each. Use after align and design for large work, or when the user says /slice or 'break this into tickets'."
---

# Slice

**Input:** `spec.md`, `design.md`, and for UI work the contract at `docs/project/contracts/<feature-slug>.md`.
**Output:** `.scratch/<feature-slug>/issues/NN-<slug>.md`, `issues/README.md` (ticket list and a Mermaid dependency graph), `STATUS.md`.
**Gate:** the user approved the breakdown and the blocking edges, and no requirement ID is uncovered.

Turn the spec and design into tickets that each finish in a verifiable state. Medium work may be a single ticket.

## 1. Draft the slices

- Each slice is a tracer bullet. It cuts a narrow but complete path through every layer (schema, API, UI, tests), not a horizontal layer. Two kinds of ticket are layer tickets by design: the contract ticket, and the UI-only and API-only tickets that build against the contract in parallel. Each of those must still be demoable on its own against stubs, and a vertical slice later joins them.
- Each slice can be demoed or verified on its own, and fits in one fresh context window.
- Every requirement ID in the spec is covered by at least one ticket, and every ticket cites the IDs it covers.
- For a UI feature, the first ticket fixes the contract: schema, stubs or mocks, and contract tests. UI and backend tickets then depend on it and can run in parallel. Vertical slices that join both sides come after.
- Do any prefactoring first. Make the change easy, then make the easy change.
- Give each ticket a `Touches:` line naming the modules it will change (module names, not file paths). `build` uses it to decide which tickets can run at the same time.
- Give each ticket its blocking edges, meaning the tickets that must finish before it can start.

A wide mechanical change that breaks many call sites at once, such as renaming a column or retyping a shared symbol, cannot land as vertical slices. Sequence it as expand, migrate, contract. Expand adds the new form next to the old one. Migrate moves call sites in batches sized by blast radius, one ticket per batch. Contract deletes the old form once no caller remains, in a ticket blocked by every batch.

## 2. Review with the user

Present a numbered list. Per ticket show the title, what it blocks on, and the end-to-end behavior it delivers. Ask whether the granularity is right, whether each edge is a real dependency, and whether any tickets should merge or split. Iterate until the user approves.

## 3. Write the files

Number from `01` in dependency order, blockers first, one file per ticket. Avoid file paths and code snippets, which go stale.

```
# 01: <title>

Status: ready-for-agent
Blocked by: None
Covers: REQ-001, REQ-002
Touches: <module names>
Layer: <ui|api|data|contract|slice, UI projects only>

## What to build
The end-to-end behavior this ticket makes work, from the user's point of view.

## Acceptance criteria
- [ ] ...

## Notes
Appended by `build`: decisions, surprises, links to commits.
```

Work the frontier, which is every ticket whose blockers are all `resolved`. For a linear chain that is top to bottom.
