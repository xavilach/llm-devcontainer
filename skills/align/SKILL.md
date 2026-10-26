---
name: align
description: "Phase 1 of engineering-flow. Interview the user until the goal, scope and test seams are agreed, then write spec.md. Use before building anything non-trivial, or when the user says /align, 'grill me' or 'write a spec'."
---

# Align

**Input:** a feature from `docs/project/roadmap.md`, or the user's request.
**Output:** `.scratch/<feature-slug>/spec.md`, `decisions.md`, `STATUS.md`; new requirement IDs in `docs/project/requirements.md`; new terms in `GLOSSARY.md`.
**Gate:** the user approved the spec and the test seams, every story cites requirement IDs, `decisions.md` is complete, and no open question remains.

Settle what to build and why before any design or code. For a new project or a first UI feature, run `define` first.

## 1. Restate

Say in your own words what you think the goal is and what problem it solves. Ask for a yes or a correction. A small, clear request can stop here and go straight to step 3.

## 2. Interview in rounds

Treat the plan as a tree of decisions where each decision unlocks the ones below it. The frontier is every decision whose prerequisites are already settled.

- Ask the whole frontier in one round. Number the questions and give your recommended answer to each, worded so that "yes" accepts it.
- Wait for the answers, then recompute the frontier and ask the next round. A question that depends on another open question waits for a later round.
- Look up facts yourself. Read the code, the docs and the history, and use a subagent for wide searches. Ask the user only about decisions, never about facts you can find.
- Write each question and its answer to `decisions.md` as you go, with an ID (`D-001`), the decision and the reason. Never rely on the chat as the record.
- For a feature with a UI, the same rounds cover both sides. Ask about the screens, states (loading, empty, error, partial) and copy alongside the data, validation and permissions behind them. Do not finish one side first.
- The interview ends when the frontier is empty and nothing is silently assumed. Do not act on it until the user confirms the shared understanding.

Format for each question:

```
Q1. <title>
<question, with options if there are any>
Recommended: <answer>
```

## 3. Agree the test seams

A seam is a public boundary where behavior can be observed without reaching inside. Propose the seams to test, preferring existing ones and the highest one that works. The fewer seams, the better. Give each a one-line note on what it catches and what it misses. Get the user's confirmation. `build` writes tests only at agreed seams.

## 4. Write the spec

Synthesize the conversation. Do not interview again at this point. Use the domain vocabulary from `GLOSSARY.md` if it exists. Do not put file paths or code snippets in the spec, because they go stale. The one exception is a prototype snippet that pins a decision more exactly than prose can, such as a state machine or a type shape.

```
# <Feature>

## Problem
The problem as the user experiences it.

## Requirements covered
IDs from `docs/project/requirements.md`. Add new requirements there with the next free ID, tagged by layer (`ui`, `api`, `data`, `ops`, `cross`).

## Solution
What the user will be able to do, in their terms.

## User stories
A numbered list, each as "As a <actor>, I want <capability>, so that <benefit>", with the requirement IDs it covers. Cover every behavior. For UI work, write each story once and note what it needs from the screen and from the backend.

## Decisions
Modules touched, interfaces changed, schema or API contracts, architectural choices.

## Testing
The agreed seams, what a good test looks like here, similar tests already in the repo.

## Out of scope
What this will not do.

## Open questions
Anything still unresolved. Empty when the gate is met.
```

## 5. Record

Promote any decision that outlives the feature to an ADR in `docs/adr/`. Add new terms to `GLOSSARY.md`. Update `STATUS.md` with the gate result and the list of outputs.
